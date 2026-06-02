import Foundation

/// Reads entries from ZIP archives.
///
/// Supports stored (method 0) and deflated (method 8) entries.
/// Scans backwards from the end of the archive to locate the End of
/// Central Directory record, then walks the central directory to
/// extract each entry.
///
/// ## Usage
/// ```swift
/// // Read all entries from a file
/// let entries = try ZIPReader.read(from: fileURL)
///
/// // Read all entries from in-memory data
/// let entries = try ZIPReader.read(from: archiveData)
///
/// // Read a single entry by path
/// if let entry = try ZIPReader.readEntry(named: "hello.txt", from: data) {
///     print(String(data: entry.data, encoding: .utf8)!)
/// }
///
/// // List entry paths without decompressing
/// let paths = try ZIPReader.listEntries(in: data)
/// ```
public enum ZIPReader: Sendable {

    // MARK: - ZIP Format Constants

    /// End of Central Directory signature.
    private static let eocdSignature: UInt32 = 0x06054B50
    /// Central Directory file header signature.
    private static let centralDirSignature: UInt32 = 0x02014B50
    /// Local file header signature.
    private static let localHeaderSignature: UInt32 = 0x04034B50
    /// Minimum size of the EOCD record (no comment).
    private static let eocdMinSize = 22
    /// Maximum distance to scan backwards for EOCD (22 + max comment of 65535).
    private static let eocdMaxScanDistance = 65557

    // MARK: - Internal Types

    /// ZIP64 End of Central Directory locator signature.
    private static let zip64LocatorSignature: UInt32 = 0x07064B50
    /// ZIP64 End of Central Directory record signature.
    private static let zip64EOCDSignature: UInt32 = 0x06064B50

    /// Parsed central directory record used during reading.
    private struct CentralDirectoryRecord {
        let compressionMethod: UInt16
        let modTime: UInt16
        let modDate: UInt16
        let crc32: UInt32
        let compressedSize: UInt64
        let uncompressedSize: UInt64
        let name: String
        let localHeaderOffset: UInt64
    }

    // MARK: - Public API

    /// Reads all entries from a ZIP archive at the given URL.
    ///
    /// Supports stored (method 0) and deflated (method 8) entries.
    /// - Parameter url: The ZIP file URL.
    /// - Returns: All entries with their decompressed data.
    /// - Throws: ``ZIPError`` if the archive is malformed or uses unsupported features.
    public static func read(from url: URL) throws -> [ZIPEntry] {
        let data = try Data(contentsOf: url)
        return try read(from: data)
    }

    /// Reads all entries from ZIP data in memory.
    ///
    /// - Parameter data: The raw ZIP archive bytes.
    /// - Returns: All entries with their decompressed data.
    /// - Throws: ``ZIPError`` if the archive is malformed or uses unsupported features.
    public static func read(from data: Data) throws -> [ZIPEntry] {
        let records = try parseCentralDirectory(from: data)
        var entries: [ZIPEntry] = []
        entries.reserveCapacity(records.count)

        for record in records {
            let entry = try extractEntry(record: record, from: data)
            entries.append(entry)
        }

        return entries
    }

    /// Reads a single entry by path from ZIP data.
    ///
    /// - Parameters:
    ///   - path: The entry path to search for.
    ///   - data: The raw ZIP archive bytes.
    /// - Returns: The matching entry, or `nil` if the path is not found.
    /// - Throws: ``ZIPError`` if the archive is malformed or uses unsupported features.
    public static func readEntry(named path: String, from data: Data) throws -> ZIPEntry? {
        let records = try parseCentralDirectory(from: data)

        guard let record = records.first(where: { $0.name == path }) else {
            return nil
        }

        return try extractEntry(record: record, from: data)
    }

    /// Lists all entry paths without decompressing data.
    ///
    /// - Parameter data: The raw ZIP archive bytes.
    /// - Returns: The paths of all entries in the archive, in order.
    /// - Throws: ``ZIPError`` if the archive is malformed.
    public static func listEntries(in data: Data) throws -> [String] {
        let records = try parseCentralDirectory(from: data)
        return records.map(\.name)
    }

    // MARK: - Private Implementation

    /// Locates the End of Central Directory record by scanning backwards.
    ///
    /// - Parameter data: The raw ZIP archive bytes.
    /// - Returns: The byte offset of the EOCD signature within `data`.
    /// - Throws: ``ZIPError/missingEndOfCentralDirectory`` if no EOCD is found,
    ///           ``ZIPError/truncatedArchive`` if the data is too small.
    private static func findEOCD(in data: Data) throws -> Int {
        guard data.count >= eocdMinSize else {
            throw ZIPError.truncatedArchive
        }

        let scanLimit = min(data.count, eocdMaxScanDistance)
        // Scan backwards from the end
        for offset in stride(from: eocdMinSize, through: scanLimit, by: 1) {
            let candidateOffset = data.count - offset
            guard candidateOffset + 4 <= data.count else { continue }
            let signature = data.readUInt32(at: candidateOffset)
            if signature == eocdSignature {
                return candidateOffset
            }
        }

        throw ZIPError.missingEndOfCentralDirectory
    }

    /// Parses the central directory to produce an array of records.
    ///
    /// - Parameter data: The raw ZIP archive bytes.
    /// - Returns: An array of central directory records in order.
    /// - Throws: ``ZIPError`` if the archive structure is invalid.
    private static func parseCentralDirectory(from data: Data) throws -> [CentralDirectoryRecord] {
        let eocdOffset = try findEOCD(in: data)

        guard eocdOffset + eocdMinSize <= data.count else {
            throw ZIPError.truncatedArchive
        }

        var entryCount = Int(data.readUInt16(at: eocdOffset + 8))
        var centralDirOffset = Int(data.readUInt32(at: eocdOffset + 16))

        // Check for ZIP64 EOCD locator (20 bytes before the standard EOCD)
        if eocdOffset >= 20 {
            let locatorOffset = eocdOffset - 20
            if data.readUInt32(at: locatorOffset) == zip64LocatorSignature {
                let zip64EOCDOffset = Int(data.readUInt64(at: locatorOffset + 8))
                if zip64EOCDOffset + 56 <= data.count,
                   data.readUInt32(at: zip64EOCDOffset) == zip64EOCDSignature
                {
                    entryCount = Int(data.readUInt64(at: zip64EOCDOffset + 32))
                    centralDirOffset = Int(data.readUInt64(at: zip64EOCDOffset + 48))
                }
            }
        }

        guard centralDirOffset >= 0, centralDirOffset <= data.count else {
            throw ZIPError.truncatedArchive
        }

        var records: [CentralDirectoryRecord] = []
        records.reserveCapacity(entryCount)
        var cursor = centralDirOffset

        for _ in 0..<entryCount {
            guard cursor + 46 <= data.count else {
                throw ZIPError.truncatedArchive
            }

            let signature = data.readUInt32(at: cursor)
            guard signature == centralDirSignature else {
                throw ZIPError.invalidSignature
            }

            let compressionMethod = data.readUInt16(at: cursor + 10)
            let modTime = data.readUInt16(at: cursor + 12)
            let modDate = data.readUInt16(at: cursor + 14)
            let crc32 = data.readUInt32(at: cursor + 16)
            var compressedSize = UInt64(data.readUInt32(at: cursor + 20))
            var uncompressedSize = UInt64(data.readUInt32(at: cursor + 24))
            let nameLength = Int(data.readUInt16(at: cursor + 28))
            let extraLength = Int(data.readUInt16(at: cursor + 30))
            let commentLength = Int(data.readUInt16(at: cursor + 32))
            var localHeaderOffset = UInt64(data.readUInt32(at: cursor + 42))

            let nameStart = cursor + 46
            let nameEnd = nameStart + nameLength
            guard nameEnd <= data.count else {
                throw ZIPError.truncatedArchive
            }

            let nameData = data[nameStart..<nameEnd]
            let name = String(decoding: nameData, as: UTF8.self)

            // Parse ZIP64 extra field if sizes or offset are 0xFFFFFFFF
            if extraLength > 0 {
                let extraStart = nameEnd
                let extraEnd = extraStart + extraLength
                guard extraEnd <= data.count else {
                    throw ZIPError.truncatedArchive
                }
                parseZip64Extra(
                    data: data, start: extraStart, length: extraLength,
                    uncompressedSize: &uncompressedSize,
                    compressedSize: &compressedSize,
                    localHeaderOffset: &localHeaderOffset
                )
            }

            records.append(CentralDirectoryRecord(
                compressionMethod: compressionMethod,
                modTime: modTime,
                modDate: modDate,
                crc32: crc32,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                name: name,
                localHeaderOffset: localHeaderOffset
            ))

            cursor = nameEnd + extraLength + commentLength
        }

        return records
    }

    /// Parses the ZIP64 extended information extra field (tag 0x0001).
    ///
    /// Fields are present in order only when the corresponding standard
    /// field is set to 0xFFFFFFFF (or 0xFFFF for disk number).
    private static func parseZip64Extra(
        data: Data, start: Int, length: Int,
        uncompressedSize: inout UInt64,
        compressedSize: inout UInt64,
        localHeaderOffset: inout UInt64
    ) {
        var pos = start
        let end = start + length

        while pos + 4 <= end {
            let tag = data.readUInt16(at: pos)
            let size = Int(data.readUInt16(at: pos + 2))
            let fieldStart = pos + 4

            guard fieldStart + size <= end else { break }

            if tag == 0x0001 {
                var fieldPos = fieldStart
                if uncompressedSize == 0xFFFFFFFF, fieldPos + 8 <= fieldStart + size {
                    uncompressedSize = data.readUInt64(at: fieldPos)
                    fieldPos += 8
                }
                if compressedSize == 0xFFFFFFFF, fieldPos + 8 <= fieldStart + size {
                    compressedSize = data.readUInt64(at: fieldPos)
                    fieldPos += 8
                }
                if localHeaderOffset == 0xFFFFFFFF, fieldPos + 8 <= fieldStart + size {
                    localHeaderOffset = data.readUInt64(at: fieldPos)
                }
                return
            }

            pos = fieldStart + size
        }
    }

    /// Extracts a single entry from the archive using its central directory record.
    ///
    /// - Parameters:
    ///   - record: The central directory record describing the entry.
    ///   - data: The raw ZIP archive bytes.
    /// - Returns: The fully-decompressed ``ZIPEntry``.
    /// - Throws: ``ZIPError`` on signature mismatch, unsupported method, CRC failure, etc.
    private static func extractEntry(
        record: CentralDirectoryRecord,
        from data: Data
    ) throws -> ZIPEntry {
        let localOffset = Int(record.localHeaderOffset)

        guard localOffset + 30 <= data.count else {
            throw ZIPError.truncatedArchive
        }

        let localSignature = data.readUInt32(at: localOffset)
        guard localSignature == localHeaderSignature else {
            throw ZIPError.invalidSignature
        }

        let localNameLength = Int(data.readUInt16(at: localOffset + 26))
        let localExtraLength = Int(data.readUInt16(at: localOffset + 28))

        let dataStart = localOffset + 30 + localNameLength + localExtraLength
        let compressedSize = Int(record.compressedSize)
        let dataEnd = dataStart + compressedSize

        guard dataEnd <= data.count else {
            throw ZIPError.truncatedArchive
        }

        let compressedData = data[dataStart..<dataEnd]

        guard let method = CompressionMethod(rawValue: record.compressionMethod) else {
            throw ZIPError.unsupportedCompressionMethod(record.compressionMethod)
        }

        let decompressedData: Data
        switch method {
        case .stored:
            decompressedData = Data(compressedData)
        case .deflated:
            decompressedData = try Deflate.decompress(
                Data(compressedData),
                uncompressedSize: Int(record.uncompressedSize)
            )
        }

        // Verify CRC-32
        let actualCRC = CRC32.calculate(decompressedData)
        guard actualCRC == record.crc32 else {
            throw ZIPError.checksumMismatch(
                path: record.name,
                expected: record.crc32,
                actual: actualCRC
            )
        }

        let modificationDate = DOSTime.decode(time: record.modTime, date: record.modDate)
        return ZIPEntry(
            path: record.name,
            data: decompressedData,
            method: method,
            modificationDate: modificationDate
        )
    }
}
