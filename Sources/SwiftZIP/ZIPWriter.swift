import Foundation

/// Creates ZIP archives from a collection of entries.
///
/// All entries are written using the stored method (no compression).
/// Deflate compression is not yet supported.
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
        var centralEntryCount: UInt16 = 0

        for entry in entries {
            guard entry.method == .stored else {
                throw ZIPError.unsupportedCompressionMethod(entry.method.rawValue)
            }

            let localHeaderOffset = UInt32(archive.count)
            let pathData = Data(entry.path.utf8)
            let crc = CRC32.calculate(entry.data)
            let size = UInt32(entry.data.count)

            // Local file header
            var local = Data()
            local.appendUInt32(0x04034b50)                  // signature
            local.appendUInt16(20)                          // version needed
            local.appendUInt16(0)                           // general purpose bit flag
            local.appendUInt16(entry.method.rawValue)       // compression method
            local.appendUInt16(0)                           // last mod file time
            local.appendUInt16(0)                           // last mod file date
            local.appendUInt32(crc)                         // CRC-32
            local.appendUInt32(size)                        // compressed size
            local.appendUInt32(size)                        // uncompressed size
            local.appendUInt16(UInt16(pathData.count))      // file name length
            local.appendUInt16(0)                           // extra field length
            local.append(pathData)
            local.append(entry.data)
            archive.append(local)

            // Central directory header
            var central = Data()
            central.appendUInt32(0x02014b50)                // signature
            central.appendUInt16(20)                        // version made by
            central.appendUInt16(20)                        // version needed
            central.appendUInt16(0)                         // general purpose bit flag
            central.appendUInt16(entry.method.rawValue)     // compression method
            central.appendUInt16(0)                         // last mod file time
            central.appendUInt16(0)                         // last mod file date
            central.appendUInt32(crc)                       // CRC-32
            central.appendUInt32(size)                      // compressed size
            central.appendUInt32(size)                      // uncompressed size
            central.appendUInt16(UInt16(pathData.count))    // file name length
            central.appendUInt16(0)                         // extra field length
            central.appendUInt16(0)                         // file comment length
            central.appendUInt16(0)                         // disk number start
            central.appendUInt16(0)                         // internal file attributes
            central.appendUInt32(0)                         // external file attributes
            central.appendUInt32(localHeaderOffset)         // relative offset of local header
            central.append(pathData)
            centralDirectory.append(central)
            centralEntryCount += 1
        }

        let centralDirOffset = UInt32(archive.count)
        archive.append(centralDirectory)
        let centralDirSize = UInt32(centralDirectory.count)

        // End of central directory record
        var eocd = Data()
        eocd.appendUInt32(0x06054b50)                       // signature
        eocd.appendUInt16(0)                                // number of this disk
        eocd.appendUInt16(0)                                // disk where central dir starts
        eocd.appendUInt16(centralEntryCount)                // entries on this disk
        eocd.appendUInt16(centralEntryCount)                // total entries
        eocd.appendUInt32(centralDirSize)                   // size of central directory
        eocd.appendUInt32(centralDirOffset)                 // offset of central directory
        eocd.appendUInt16(0)                                // ZIP file comment length
        archive.append(eocd)

        return archive
    }
}
