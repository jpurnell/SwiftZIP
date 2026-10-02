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
/// let archiveData = try ZIPWriter.write(entries: [
///     ZIPEntry(path: "hello.txt", data: Data("Hello".utf8))
/// ])
///
/// // Read all entries from in-memory data
/// let entries = try ZIPReader.read(from: archiveData)
///
/// // Read a single entry by path
/// if let entry = try ZIPReader.readEntry(named: "hello.txt", from: archiveData) {
///     print(String(decoding: entry.data, as: UTF8.self))
/// }
///
/// // List entry paths without decompressing
/// let paths = try ZIPReader.listEntries(in: archiveData)
///
/// // Or read straight from a file
/// let fileURL = URL(fileURLWithPath: NSTemporaryDirectory())
///     .appendingPathComponent("archive.zip")
/// try archiveData.write(to: fileURL)
/// let fromDisk = try ZIPReader.read(from: fileURL)
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
    /// Size of a central directory record before its variable-length fields.
    private static let centralRecordMinSize = 46
    /// Size of a local file header before its variable-length fields.
    private static let localHeaderMinSize = 30
    /// Size of the ZIP64 End of Central Directory record without extensible data.
    private static let zip64EOCDMinSize = 56
    /// Size of the ZIP64 End of Central Directory locator.
    private static let zip64LocatorSize = 20

    // MARK: - Internal Types

    /// ZIP64 End of Central Directory locator signature.
    private static let zip64LocatorSignature: UInt32 = 0x07064B50
    /// ZIP64 End of Central Directory record signature.
    private static let zip64EOCDSignature: UInt32 = 0x06064B50

    /// Parsed central directory record used during reading.
    private struct CentralDirectoryRecord {
        let compressionMethod: UInt16
        let versionMadeBy: UInt16
        let modTime: UInt16
        let modDate: UInt16
        let crc32: UInt32
        let compressedSize: UInt64
        let uncompressedSize: UInt64
        let name: String
        let localHeaderOffset: UInt64
        let externalAttributes: UInt32
        let unixTimestamp: Int32?
    }

    // MARK: - Public API

    /// Reads all entries from a ZIP archive at the given URL.
    ///
    /// Supports stored (method 0) and deflated (method 8) entries.
    /// - Parameters:
    ///   - url: The ZIP file URL.
    ///   - limits: Ceilings on entry count and uncompressed sizes. See ``ZIPLimits``.
    /// - Returns: All entries with their decompressed data.
    /// - Throws: ``ZIPError`` if the archive is malformed or uses unsupported features,
    ///   and ``ZIPError/limitExceeded(_:value:maximum:)`` if it would cross `limits`.
    public static func read(from url: URL, limits: ZIPLimits = .default) throws -> [ZIPEntry] {
        let data = try Data(contentsOf: url)
        return try read(from: data, limits: limits)
    }

    /// Reads all entries from ZIP data in memory.
    ///
    /// The archive is treated as untrusted. Its declared sizes are checked against
    /// `limits`, and against what the format makes possible, before any entry is
    /// decompressed or any output allocated; no size or offset it declares can trap.
    ///
    /// - Parameters:
    ///   - data: The raw ZIP archive bytes. A slice of a larger buffer is accepted.
    ///   - limits: Ceilings on entry count, per-entry and total uncompressed size.
    /// - Returns: All entries with their decompressed data.
    /// - Throws: ``ZIPError`` if the archive is malformed or uses unsupported features,
    ///   and ``ZIPError/limitExceeded(_:value:maximum:)`` if it would cross `limits`.
    public static func read(from data: Data, limits: ZIPLimits = .default) throws -> [ZIPEntry] {
        let data = zeroBased(data)
        let records = try parseCentralDirectory(from: data, limits: limits)
        try validateDeclaredSizes(of: records, limits: limits)
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
    /// Only the matching entry is decompressed, so only its size is held to the
    /// per-entry and total limits; the entry count applies to the whole archive.
    ///
    /// - Parameters:
    ///   - path: The entry path to search for.
    ///   - data: The raw ZIP archive bytes. A slice of a larger buffer is accepted.
    ///   - limits: Ceilings on entry count and uncompressed size. See ``ZIPLimits``.
    /// - Returns: The matching entry, or `nil` if the path is not found.
    /// - Throws: ``ZIPError`` if the archive is malformed or uses unsupported features,
    ///   and ``ZIPError/limitExceeded(_:value:maximum:)`` if it would cross `limits`.
    public static func readEntry(
        named path: String,
        from data: Data,
        limits: ZIPLimits = .default
    ) throws -> ZIPEntry? {
        let data = zeroBased(data)
        let records = try parseCentralDirectory(from: data, limits: limits)

        guard let record = records.first(where: { $0.name == path }) else {
            return nil
        }
        try validateDeclaredSizes(of: [record], limits: limits)

        return try extractEntry(record: record, from: data)
    }

    /// Lists all entry paths without decompressing data.
    ///
    /// Nothing is decompressed, so of `limits` only the entry count applies.
    ///
    /// - Parameters:
    ///   - data: The raw ZIP archive bytes. A slice of a larger buffer is accepted.
    ///   - limits: Ceilings applied while reading; only ``ZIPLimits/maxEntryCount`` matters here.
    /// - Returns: The paths of all entries in the archive, in order.
    /// - Throws: ``ZIPError`` if the archive is malformed, and
    ///   ``ZIPError/limitExceeded(_:value:maximum:)`` if it declares too many entries.
    public static func listEntries(in data: Data, limits: ZIPLimits = .default) throws -> [String] {
        let records = try parseCentralDirectory(from: zeroBased(data), limits: limits)
        return records.map(\.name)
    }

    // MARK: - Private Implementation

    /// Rebases a slice so that offsets read from the archive index it directly.
    ///
    /// `Data` subscripts by absolute index, so a slice starting at 3 would read every
    /// archive offset three bytes early — and past its end on the last field.
    private static func zeroBased(_ data: Data) -> Data {
        data.startIndex == 0 ? data : Data(data)
    }

    /// Converts a size, count, or offset read from the archive to `Int`.
    ///
    /// - Throws: ``ZIPError/malformedHeader`` when the value does not fit, rather than
    ///   trapping as `Int(_:)` would on a value at or above 2^63 (2^31 on watchOS).
    private static func intFromArchive<Value: BinaryInteger>(_ value: Value) throws -> Int {
        guard let result = Int(exactly: value) else {
            throw ZIPError.malformedHeader
        }
        return result
    }

    /// Returns `start + length`, for a range whose start and length the archive supplied.
    ///
    /// - Throws: ``ZIPError/truncated`` when the sum overflows: such a range certainly
    ///   ends beyond the data.
    private static func rangeEnd(start: Int, length: Int) throws -> Int {
        let (end, overflow) = start.addingReportingOverflow(length)
        guard !overflow else {
            throw ZIPError.truncated
        }
        return end
    }

    /// Checks every record's declared sizes before anything is decompressed.
    ///
    /// The declared uncompressed size is what extraction allocates, so it is checked
    /// here — against `limits` and against what the compression method can produce —
    /// rather than discovered after the allocation has been made.
    ///
    /// - Throws: ``ZIPError/limitExceeded(_:value:maximum:)`` for a size over `limits`,
    ///   ``ZIPError/malformedHeader`` for sizes the method makes impossible.
    private static func validateDeclaredSizes(
        of records: [CentralDirectoryRecord],
        limits: ZIPLimits
    ) throws {
        var total: UInt64 = 0
        for record in records {
            guard record.uncompressedSize <= limits.maxEntryUncompressedSize else {
                throw ZIPError.limitExceeded(
                    .entryUncompressedSize,
                    value: record.uncompressedSize,
                    maximum: limits.maxEntryUncompressedSize
                )
            }

            switch CompressionMethod(rawValue: record.compressionMethod) {
            case .stored:
                // Stored bytes are the entry: the two sizes cannot differ.
                guard record.compressedSize == record.uncompressedSize else {
                    throw ZIPError.malformedHeader
                }
            case .deflated:
                guard Deflate.canExpand(record.compressedSize, to: record.uncompressedSize) else {
                    throw ZIPError.malformedHeader
                }
            case nil:
                // Reported as unsupported when the entry is extracted.
                break
            }

            let (sum, overflow) = total.addingReportingOverflow(record.uncompressedSize)
            guard !overflow, sum <= limits.maxTotalUncompressedSize else {
                throw ZIPError.limitExceeded(
                    .totalUncompressedSize,
                    value: overflow ? UInt64.max : sum,
                    maximum: limits.maxTotalUncompressedSize
                )
            }
            total = sum
        }
    }

    /// Locates the End of Central Directory record by scanning backwards.
    ///
    /// - Parameter data: The raw ZIP archive bytes.
    /// - Returns: The byte offset of the EOCD signature within `data`.
    /// - Throws: ``ZIPError/missingEndOfCentralDirectory`` if no EOCD is found,
    ///           ``ZIPError/truncated`` if the data is too small.
    private static func findEOCD(in data: Data) throws -> Int {
        guard data.count >= eocdMinSize else {
            throw ZIPError.truncated
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
    /// - Parameters:
    ///   - data: The raw ZIP archive bytes, zero-based.
    ///   - limits: Supplies the entry-count ceiling, checked before records are reserved.
    /// - Returns: An array of central directory records in order.
    /// - Throws: ``ZIPError`` if the archive structure is invalid.
    private static func parseCentralDirectory(
        from data: Data,
        limits: ZIPLimits
    ) throws -> [CentralDirectoryRecord] {
        let eocdOffset = try findEOCD(in: data)

        guard eocdOffset + eocdMinSize <= data.count else {
            throw ZIPError.truncated
        }

        var declaredCount = UInt64(data.readUInt16(at: eocdOffset + 8))
        var declaredOffset = UInt64(data.readUInt32(at: eocdOffset + 16))
        if let zip64 = zip64Directory(in: data, eocdOffset: eocdOffset) {
            declaredCount = zip64.entryCount
            declaredOffset = zip64.centralDirectoryOffset
        }

        let entryCount = try intFromArchive(declaredCount)
        guard entryCount <= limits.maxEntryCount else {
            throw ZIPError.limitExceeded(
                .entryCount,
                value: declaredCount,
                maximum: UInt64(clamping: limits.maxEntryCount)
            )
        }

        let centralDirOffset = try intFromArchive(declaredOffset)
        guard centralDirOffset <= data.count else {
            throw ZIPError.truncated
        }
        // Every record takes at least 46 bytes, so a count the remaining bytes cannot
        // hold is refused here, before memory is reserved for it.
        guard entryCount <= (data.count - centralDirOffset) / centralRecordMinSize else {
            throw ZIPError.truncated
        }

        var records: [CentralDirectoryRecord] = []
        records.reserveCapacity(entryCount)
        var cursor = centralDirOffset

        for _ in 0..<entryCount {
            guard cursor + centralRecordMinSize <= data.count else {
                throw ZIPError.truncated
            }

            let signature = data.readUInt32(at: cursor)
            guard signature == centralDirSignature else {
                throw ZIPError.invalidSignature
            }

            let versionMadeBy = data.readUInt16(at: cursor + 4)
            let compressionMethod = data.readUInt16(at: cursor + 10)
            let modTime = data.readUInt16(at: cursor + 12)
            let modDate = data.readUInt16(at: cursor + 14)
            let crc32 = data.readUInt32(at: cursor + 16)
            var compressedSize = UInt64(data.readUInt32(at: cursor + 20))
            var uncompressedSize = UInt64(data.readUInt32(at: cursor + 24))
            let nameLength = Int(data.readUInt16(at: cursor + 28))
            let extraLength = Int(data.readUInt16(at: cursor + 30))
            let commentLength = Int(data.readUInt16(at: cursor + 32))
            let externalAttributes = data.readUInt32(at: cursor + 38)
            var localHeaderOffset = UInt64(data.readUInt32(at: cursor + 42))

            let nameStart = cursor + centralRecordMinSize
            let nameEnd = nameStart + nameLength
            guard nameEnd <= data.count else {
                throw ZIPError.truncated
            }

            let nameData = data[nameStart..<nameEnd]
            let name = String(decoding: nameData, as: UTF8.self)

            var unixTimestamp: Int32?

            if extraLength > 0 {
                let extraStart = nameEnd
                let extraEnd = extraStart + extraLength
                guard extraEnd <= data.count else {
                    throw ZIPError.truncated
                }
                parseZip64Extra(
                    data: data, start: extraStart, length: extraLength,
                    uncompressedSize: &uncompressedSize,
                    compressedSize: &compressedSize,
                    localHeaderOffset: &localHeaderOffset
                )
                unixTimestamp = parseUTExtra(
                    data: data, start: extraStart, length: extraLength
                )
            }

            records.append(CentralDirectoryRecord(
                compressionMethod: compressionMethod,
                versionMadeBy: versionMadeBy,
                modTime: modTime,
                modDate: modDate,
                crc32: crc32,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                name: name,
                localHeaderOffset: localHeaderOffset,
                externalAttributes: externalAttributes,
                unixTimestamp: unixTimestamp
            ))

            cursor = nameEnd + extraLength + commentLength
        }

        return records
    }

    /// Reads the entry count and central directory offset from a ZIP64 EOCD record.
    ///
    /// - Returns: The record's fields, or `nil` when there is no ZIP64 locator directly
    ///   before the standard EOCD, or it points somewhere that holds no ZIP64 record —
    ///   including an offset too large to represent. The standard EOCD then stands.
    private static func zip64Directory(
        in data: Data,
        eocdOffset: Int
    ) -> (entryCount: UInt64, centralDirectoryOffset: UInt64)? {
        guard eocdOffset >= zip64LocatorSize else { return nil }
        let locatorOffset = eocdOffset - zip64LocatorSize
        guard data.readUInt32(at: locatorOffset) == zip64LocatorSignature else { return nil }

        guard let recordOffset = Int(exactly: data.readUInt64(at: locatorOffset + 8)),
              recordOffset <= data.count - zip64EOCDMinSize,
              data.readUInt32(at: recordOffset) == zip64EOCDSignature
        else {
            return nil
        }
        return (
            entryCount: data.readUInt64(at: recordOffset + 32),
            centralDirectoryOffset: data.readUInt64(at: recordOffset + 48)
        )
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

    /// Parses the Universal Time extra field (tag 0x5455) for mtime.
    ///
    /// - Parameters:
    ///   - data: The raw archive bytes.
    ///   - start: Start offset of the extra field area.
    ///   - length: Total length of extra fields.
    /// - Returns: The Unix timestamp (seconds since epoch) if found, or `nil`.
    private static func parseUTExtra(data: Data, start: Int, length: Int) -> Int32? {
        var pos = start
        let end = start + length

        while pos + 4 <= end {
            let tag = data.readUInt16(at: pos)
            let size = Int(data.readUInt16(at: pos + 2))
            let fieldStart = pos + 4

            guard fieldStart + size <= end else { break }

            if tag == 0x5455, size >= 5 {
                let flags = data[fieldStart]
                guard flags & 0x01 != 0 else { return nil }
                let rawTime = data.readUInt32(at: fieldStart + 1)
                return Int32(bitPattern: rawTime)
            }

            pos = fieldStart + size
        }
        return nil
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
        let localOffset = try intFromArchive(record.localHeaderOffset)

        guard try rangeEnd(start: localOffset, length: localHeaderMinSize) <= data.count else {
            throw ZIPError.truncated
        }

        let localSignature = data.readUInt32(at: localOffset)
        guard localSignature == localHeaderSignature else {
            throw ZIPError.invalidSignature
        }

        let localNameLength = Int(data.readUInt16(at: localOffset + 26))
        let localExtraLength = Int(data.readUInt16(at: localOffset + 28))

        // Bounded: localOffset is within the data and the two lengths are 16-bit.
        let dataStart = localOffset + localHeaderMinSize + localNameLength + localExtraLength
        let compressedSize = try intFromArchive(record.compressedSize)
        let dataEnd = try rangeEnd(start: dataStart, length: compressedSize)

        guard dataEnd <= data.count else {
            throw ZIPError.truncated
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
                uncompressedSize: try intFromArchive(record.uncompressedSize)
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

        let modificationDate: Date?
        if let unixTime = record.unixTimestamp {
            modificationDate = Date(timeIntervalSince1970: TimeInterval(unixTime))
        } else {
            modificationDate = DOSTime.decode(time: record.modTime, date: record.modDate)
        }

        let unixPermissions: UInt16?
        let platform = record.versionMadeBy >> 8
        if platform == 3 {
            let rawPerms = UInt16(record.externalAttributes >> 16) & 0o7777
            unixPermissions = rawPerms > 0 ? rawPerms : nil
        } else {
            unixPermissions = nil
        }

        return ZIPEntry(
            path: record.name,
            data: decompressedData,
            method: method,
            modificationDate: modificationDate,
            unixPermissions: unixPermissions
        )
    }
}
