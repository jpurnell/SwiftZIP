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

    /// Parsed central directory record used during reading.
    private struct CentralDirectoryRecord {
        let compressionMethod: UInt16
        let crc32: UInt32
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let name: String
        let localHeaderOffset: UInt32
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
        // Step 1: Find EOCD
        let eocdOffset = try findEOCD(in: data)

        // Step 2: Parse EOCD fields
        guard eocdOffset + eocdMinSize <= data.count else {
            throw ZIPError.truncatedArchive
        }

        let entryCount = Int(data.readUInt16(at: eocdOffset + 8))
        let centralDirOffset = Int(data.readUInt32(at: eocdOffset + 16))

        guard centralDirOffset >= 0, centralDirOffset <= data.count else {
            throw ZIPError.truncatedArchive
        }

        // Step 3: Parse each central directory entry
        var records: [CentralDirectoryRecord] = []
        records.reserveCapacity(entryCount)
        var cursor = centralDirOffset

        for _ in 0..<entryCount {
            // Verify we have at least the fixed-size portion (46 bytes)
            guard cursor + 46 <= data.count else {
                throw ZIPError.truncatedArchive
            }

            let signature = data.readUInt32(at: cursor)
            guard signature == centralDirSignature else {
                throw ZIPError.invalidSignature
            }

            let compressionMethod = data.readUInt16(at: cursor + 10)
            let crc32 = data.readUInt32(at: cursor + 16)
            let compressedSize = data.readUInt32(at: cursor + 20)
            let uncompressedSize = data.readUInt32(at: cursor + 24)
            let nameLength = Int(data.readUInt16(at: cursor + 28))
            let extraLength = Int(data.readUInt16(at: cursor + 30))
            let commentLength = Int(data.readUInt16(at: cursor + 32))
            let localHeaderOffset = data.readUInt32(at: cursor + 42)

            let nameStart = cursor + 46
            let nameEnd = nameStart + nameLength
            guard nameEnd <= data.count else {
                throw ZIPError.truncatedArchive
            }

            let nameData = data[nameStart..<nameEnd]
            let name = String(decoding: nameData, as: UTF8.self)

            records.append(CentralDirectoryRecord(
                compressionMethod: compressionMethod,
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

        // Verify local header signature
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

        // Determine the compression method
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

        return ZIPEntry(path: record.name, data: decompressedData, method: method)
    }
}
