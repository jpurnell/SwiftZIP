import Foundation

/// Creates ZIP archives from a collection of entries.
///
/// Supports both stored (method 0) and deflated (method 8) entries.
/// When deflate is requested, the writer falls back to stored if
/// compression does not reduce size.
///
/// ## Usage
/// ```swift
/// let entries = [
///     ZIPEntry(path: "hello.txt", data: Data("Hello".utf8)),
///     ZIPEntry(path: "world.txt", data: Data("World".utf8)),
/// ]
/// // Write to a file
/// try ZIPWriter.write(entries: entries, to: fileURL)
/// // Or get the archive bytes directly
/// let archiveData = try ZIPWriter.write(entries: entries)
/// ```
public enum ZIPWriter: Sendable {

    /// Writes entries to a ZIP archive at the given file URL.
    ///
    /// - Parameters:
    ///   - entries: The entries to include in the archive.
    ///   - url: The file URL to write the archive to.
    /// - Throws: An error if the archive cannot be written to the URL.
    public static func write(entries: [ZIPEntry], to url: URL) throws {
        let data = try write(entries: entries)
        try data.write(to: url)
    }

    /// Writes entries to a ZIP archive and returns the archive data.
    ///
    /// - Parameter entries: The entries to include in the archive.
    /// - Returns: The complete ZIP archive as `Data`.
    /// - Throws: ``ZIPError/unsupportedCompressionMethod(_:)`` if any entry
    ///   uses a compression method other than `.stored`.
    public static func write(entries: [ZIPEntry]) throws -> Data {
        var archive = Data()
        var centralDirectory = Data()
        var entryCount: UInt64 = 0

        for entry in entries {
            let localHeaderOffset = UInt64(archive.count)
            let pathData = Data(entry.path.utf8)
            let crc = CRC32.calculate(entry.data)
            let uncompressedSize64 = UInt64(entry.data.count)

            let timestamp = DOSTime.encode(entry.modificationDate ?? Date())
            let fileData: Data
            let method: CompressionMethod
            let compressedSize64: UInt64

            switch entry.method {
            case .stored:
                fileData = entry.data
                method = .stored
                compressedSize64 = uncompressedSize64
            case .deflated:
                if entry.data.isEmpty {
                    fileData = Data()
                    method = .stored
                    compressedSize64 = 0
                } else {
                    let compressed = try Deflate.compress(entry.data)
                    if compressed.count < entry.data.count {
                        fileData = compressed
                        method = .deflated
                        compressedSize64 = UInt64(compressed.count)
                    } else {
                        fileData = entry.data
                        method = .stored
                        compressedSize64 = uncompressedSize64
                    }
                }
            }

            let needsZip64Entry = compressedSize64 >= 0xFFFFFFFF
                || uncompressedSize64 >= 0xFFFFFFFF
                || localHeaderOffset >= 0xFFFFFFFF

            let localCompressed = needsZip64Entry ? UInt32(0xFFFFFFFF) : UInt32(compressedSize64)
            let localUncompressed = needsZip64Entry ? UInt32(0xFFFFFFFF) : UInt32(uncompressedSize64)
            let localOffset32 = needsZip64Entry ? UInt32(0xFFFFFFFF) : UInt32(localHeaderOffset)

            var zip64Extra = Data()
            if needsZip64Entry {
                zip64Extra.appendUInt16(0x0001)
                zip64Extra.appendUInt16(24)
                zip64Extra.appendUInt64(uncompressedSize64)
                zip64Extra.appendUInt64(compressedSize64)
                zip64Extra.appendUInt64(localHeaderOffset)
            }

            // Local file header
            var local = Data()
            local.appendUInt32(0x04034b50)                  // signature
            local.appendUInt16(needsZip64Entry ? 45 : 20)   // version needed
            local.appendUInt16(0)                           // general purpose bit flag
            local.appendUInt16(method.rawValue)             // compression method
            local.appendUInt16(timestamp.time)              // last mod file time
            local.appendUInt16(timestamp.date)              // last mod file date
            local.appendUInt32(crc)                         // CRC-32
            local.appendUInt32(localCompressed)             // compressed size
            local.appendUInt32(localUncompressed)           // uncompressed size
            local.appendUInt16(UInt16(pathData.count))      // file name length
            local.appendUInt16(UInt16(zip64Extra.count))    // extra field length
            local.append(pathData)
            if !zip64Extra.isEmpty { local.append(zip64Extra) }
            local.append(fileData)
            archive.append(local)

            // Central directory header
            var central = Data()
            central.appendUInt32(0x02014b50)                // signature
            central.appendUInt16(needsZip64Entry ? 45 : 20) // version made by
            central.appendUInt16(needsZip64Entry ? 45 : 20) // version needed
            central.appendUInt16(0)                         // general purpose bit flag
            central.appendUInt16(method.rawValue)           // compression method
            central.appendUInt16(timestamp.time)            // last mod file time
            central.appendUInt16(timestamp.date)            // last mod file date
            central.appendUInt32(crc)                       // CRC-32
            central.appendUInt32(localCompressed)           // compressed size
            central.appendUInt32(localUncompressed)         // uncompressed size
            central.appendUInt16(UInt16(pathData.count))    // file name length
            central.appendUInt16(UInt16(zip64Extra.count))  // extra field length
            central.appendUInt16(0)                         // file comment length
            central.appendUInt16(0)                         // disk number start
            central.appendUInt16(0)                         // internal file attributes
            central.appendUInt32(0)                         // external file attributes
            central.appendUInt32(localOffset32)             // relative offset of local header
            central.append(pathData)
            if !zip64Extra.isEmpty { central.append(zip64Extra) }
            centralDirectory.append(central)
            entryCount += 1
        }

        let centralDirOffset = UInt64(archive.count)
        archive.append(centralDirectory)
        let centralDirSize = UInt64(centralDirectory.count)

        let needsZip64 = entryCount > 0xFFFE
            || centralDirOffset >= 0xFFFFFFFF
            || centralDirSize >= 0xFFFFFFFF

        if needsZip64 {
            let zip64EOCDOffset = UInt64(archive.count)

            // ZIP64 End of Central Directory record
            var zip64EOCD = Data()
            zip64EOCD.appendUInt32(0x06064b50)              // signature
            zip64EOCD.appendUInt64(44)                      // size of remaining record
            zip64EOCD.appendUInt16(45)                      // version made by
            zip64EOCD.appendUInt16(45)                      // version needed
            zip64EOCD.appendUInt32(0)                       // disk number
            zip64EOCD.appendUInt32(0)                       // disk with CD start
            zip64EOCD.appendUInt64(entryCount)              // entries on this disk
            zip64EOCD.appendUInt64(entryCount)              // total entries
            zip64EOCD.appendUInt64(centralDirSize)          // CD size
            zip64EOCD.appendUInt64(centralDirOffset)        // CD offset
            archive.append(zip64EOCD)

            // ZIP64 End of Central Directory locator
            var locator = Data()
            locator.appendUInt32(0x07064b50)                // signature
            locator.appendUInt32(0)                         // disk with ZIP64 EOCD
            locator.appendUInt64(zip64EOCDOffset)           // offset of ZIP64 EOCD
            locator.appendUInt32(1)                         // total disks
            archive.append(locator)
        }

        let eocdEntryCount = needsZip64 ? UInt16(0xFFFF) : UInt16(entryCount)
        let eocdCDSize = needsZip64 ? UInt32(0xFFFFFFFF) : UInt32(centralDirSize)
        let eocdCDOffset = needsZip64 ? UInt32(0xFFFFFFFF) : UInt32(centralDirOffset)

        // End of central directory record
        var eocd = Data()
        eocd.appendUInt32(0x06054b50)                       // signature
        eocd.appendUInt16(0)                                // number of this disk
        eocd.appendUInt16(0)                                // disk where central dir starts
        eocd.appendUInt16(eocdEntryCount)                   // entries on this disk
        eocd.appendUInt16(eocdEntryCount)                   // total entries
        eocd.appendUInt32(eocdCDSize)                       // size of central directory
        eocd.appendUInt32(eocdCDOffset)                     // offset of central directory
        eocd.appendUInt16(0)                                // ZIP file comment length
        archive.append(eocd)

        return archive
    }
}
