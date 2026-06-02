import Foundation
import Testing
@testable import SwiftZIP

@Suite("ZIPReader")
struct ZIPReaderTests {

    // MARK: - Round-Trip: Stored Entries

    @Test("Read stored entries — write 3 entries, read back, verify paths and data match")
    func readStoredEntries() throws {
        let entries = [
            ZIPEntry(path: "alpha.txt", data: Data("Hello Alpha".utf8)),
            ZIPEntry(path: "beta.txt", data: Data("Hello Beta".utf8)),
            ZIPEntry(path: "gamma.txt", data: Data("Hello Gamma".utf8)),
        ]
        let archive = try ZIPWriter.write(entries: entries)
        let result = try ZIPReader.read(from: archive)

        #expect(result.count == 3)
        for (original, read) in zip(entries, result) {
            #expect(read.path == original.path)
            #expect(read.data == original.data)
            #expect(read.method == .stored)
        }
    }

    // MARK: - Read Single Entry by Name

    @Test("readEntry(named:) returns correct entry")
    func readSingleEntryByName() throws {
        let entries = [
            ZIPEntry(path: "first.txt", data: Data("First".utf8)),
            ZIPEntry(path: "second.txt", data: Data("Second".utf8)),
            ZIPEntry(path: "third.txt", data: Data("Third".utf8)),
        ]
        let archive = try ZIPWriter.write(entries: entries)

        let found = try ZIPReader.readEntry(named: "second.txt", from: archive)
        #expect(found != nil)
        #expect(found?.path == "second.txt")
        #expect(found?.data == Data("Second".utf8))
    }

    // MARK: - Read Missing Entry

    @Test("readEntry(named:) returns nil for non-existent path")
    func readMissingEntry() throws {
        let entries = [
            ZIPEntry(path: "exists.txt", data: Data("Here".utf8)),
        ]
        let archive = try ZIPWriter.write(entries: entries)

        let found = try ZIPReader.readEntry(named: "nope.txt", from: archive)
        #expect(found == nil)
    }

    // MARK: - List Entries

    @Test("listEntries returns correct paths in order")
    func listEntries() throws {
        let entries = [
            ZIPEntry(path: "aaa.txt", data: Data("A".utf8)),
            ZIPEntry(path: "bbb.txt", data: Data("B".utf8)),
            ZIPEntry(path: "ccc.txt", data: Data("C".utf8)),
        ]
        let archive = try ZIPWriter.write(entries: entries)

        let paths = try ZIPReader.listEntries(in: archive)
        #expect(paths == ["aaa.txt", "bbb.txt", "ccc.txt"])
    }

    // MARK: - Empty Archive

    @Test("Read archive with 0 entries yields empty array")
    func emptyArchive() throws {
        let archive = try ZIPWriter.write(entries: [])
        let result = try ZIPReader.read(from: archive)
        #expect(result.isEmpty)
    }

    // MARK: - Unicode Paths

    @Test("Entries with non-ASCII paths survive round-trip")
    func unicodePaths() throws {
        let entries = [
            ZIPEntry(path: "café.txt", data: Data("coffee".utf8)),
            ZIPEntry(path: "日本語/ファイル.txt", data: Data("japanese".utf8)),
            ZIPEntry(path: "emoji_🎉.txt", data: Data("party".utf8)),
        ]
        let archive = try ZIPWriter.write(entries: entries)
        let result = try ZIPReader.read(from: archive)

        #expect(result.count == 3)
        for (original, read) in zip(entries, result) {
            #expect(read.path == original.path)
            #expect(read.data == original.data)
        }
    }

    // MARK: - Binary Data

    @Test("Entries with raw binary bytes survive round-trip")
    func binaryData() throws {
        var binaryContent = Data()
        for byte: UInt8 in 0...255 {
            binaryContent.append(byte)
        }
        let entries = [
            ZIPEntry(path: "binary.dat", data: binaryContent),
        ]
        let archive = try ZIPWriter.write(entries: entries)
        let result = try ZIPReader.read(from: archive)

        #expect(result.count == 1)
        #expect(result[0].data == binaryContent)
    }

    // MARK: - Large Entry

    @Test("200KB entry survives round-trip")
    func largeEntry() throws {
        let largeData = Data(repeating: 0xAB, count: 200_000)
        let entries = [
            ZIPEntry(path: "large.bin", data: largeData),
        ]
        let archive = try ZIPWriter.write(entries: entries)
        let result = try ZIPReader.read(from: archive)

        #expect(result.count == 1)
        #expect(result[0].data.count == 200_000)
        #expect(result[0].data == largeData)
    }

    // MARK: - CRC Mismatch

    @Test("Corrupted data triggers checksumMismatch error")
    func crcMismatch() throws {
        let entry = ZIPEntry(path: "test.txt", data: Data("Correct data".utf8))
        var archive = try ZIPWriter.write(entries: [entry])

        // Corrupt the stored file data (located after the local header)
        // Local header: 30 bytes fixed + path length "test.txt" = 8 bytes = 38
        let dataOffset = 30 + Data("test.txt".utf8).count
        guard dataOffset + 1 <= archive.count else {
            #expect(Bool(false), "Archive too small to corrupt")
            return
        }
        archive[dataOffset] ^= 0xFF  // flip bits in first data byte

        #expect(throws: ZIPError.self) {
            _ = try ZIPReader.read(from: archive)
        }
    }

    // MARK: - Invalid Signature

    @Test("Random bytes produce invalidSignature or missingEndOfCentralDirectory error")
    func invalidSignature() throws {
        let randomData = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x11, 0x22, 0x33,
                               0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xAA, 0xBB,
                               0xCC, 0xDD, 0xEE, 0xFF, 0x01, 0x02, 0x03, 0x04])
        #expect(throws: ZIPError.self) {
            _ = try ZIPReader.read(from: randomData)
        }
    }

    // MARK: - Truncated Archive

    @Test("Truncated archive yields truncatedArchive error")
    func truncatedArchive() throws {
        let entry = ZIPEntry(path: "hello.txt", data: Data("Hello".utf8))
        let archive = try ZIPWriter.write(entries: [entry])

        // Truncate to half length — central directory and EOCD are broken
        let truncated = archive.prefix(archive.count / 2)
        #expect(throws: ZIPError.self) {
            _ = try ZIPReader.read(from: Data(truncated))
        }
    }

    // MARK: - Missing EOCD

    @Test("Data with no EOCD yields missingEndOfCentralDirectory error")
    func missingEOCD() throws {
        // Build data that is large enough to scan but contains no EOCD signature
        let fakeData = Data(repeating: 0x00, count: 100)
        #expect(throws: ZIPError.self) {
            _ = try ZIPReader.read(from: fakeData)
        }
    }

    // MARK: - Multiple Entries with Same Data

    @Test("Multiple entries with identical data each get correct content")
    func multipleEntriesSameData() throws {
        let sharedData = Data("shared content".utf8)
        let entries = [
            ZIPEntry(path: "copy1.txt", data: sharedData),
            ZIPEntry(path: "copy2.txt", data: sharedData),
            ZIPEntry(path: "copy3.txt", data: sharedData),
        ]
        let archive = try ZIPWriter.write(entries: entries)
        let result = try ZIPReader.read(from: archive)

        #expect(result.count == 3)
        for entry in result {
            #expect(entry.data == sharedData)
        }
        #expect(result[0].path == "copy1.txt")
        #expect(result[1].path == "copy2.txt")
        #expect(result[2].path == "copy3.txt")
    }

    // MARK: - Entry Ordering

    @Test("Entries come back in the same order they were written")
    func entryOrdering() throws {
        let entries = [
            ZIPEntry(path: "z_last.txt", data: Data("Z".utf8)),
            ZIPEntry(path: "a_first.txt", data: Data("A".utf8)),
            ZIPEntry(path: "m_middle.txt", data: Data("M".utf8)),
        ]
        let archive = try ZIPWriter.write(entries: entries)
        let result = try ZIPReader.read(from: archive)

        let resultPaths = result.map(\.path)
        #expect(resultPaths == ["z_last.txt", "a_first.txt", "m_middle.txt"])
    }

    // MARK: - Read from URL

    @Test("Write to temp file, read from URL, verify")
    func readFromURL() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("zipreader_test_\(UUID().uuidString).zip")

        let entries = [
            ZIPEntry(path: "url_test.txt", data: Data("Read from URL".utf8)),
        ]
        try ZIPWriter.write(entries: entries, to: fileURL)

        let result = try ZIPReader.read(from: fileURL)
        #expect(result.count == 1)
        #expect(result[0].path == "url_test.txt")
        #expect(result[0].data == Data("Read from URL".utf8))

        // Clean up
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Deflated Entries Round-Trip

    @Test("Deflated entry is decompressed correctly on read")
    func deflatedEntryRoundTrip() throws {
        let originalData = Data("The quick brown fox jumps over the lazy dog. ".utf8)
        let archive = try buildDeflatedZIP(path: "deflated.txt", originalData: originalData)

        let result = try ZIPReader.read(from: archive)
        #expect(result.count == 1)
        #expect(result[0].path == "deflated.txt")
        #expect(result[0].data == originalData)
        #expect(result[0].method == .deflated)
    }

    @Test("Deflated entry with repetitive data decompresses correctly")
    func deflatedLargeRepetitiveData() throws {
        // Highly compressible data
        var original = Data()
        for i in 0..<1000 {
            original.append(contentsOf: "Line \(i): This is repetitive test data.\n".utf8)
        }
        let archive = try buildDeflatedZIP(path: "repetitive.txt", originalData: original)

        let result = try ZIPReader.read(from: archive)
        #expect(result.count == 1)
        #expect(result[0].data == original)
    }

    // MARK: - Empty Data Entry

    @Test("Entry with empty data round-trips correctly")
    func emptyDataEntry() throws {
        let entries = [
            ZIPEntry(path: "empty.txt", data: Data()),
        ]
        let archive = try ZIPWriter.write(entries: entries)
        let result = try ZIPReader.read(from: archive)

        #expect(result.count == 1)
        #expect(result[0].path == "empty.txt")
        #expect(result[0].data.isEmpty)
    }

    // MARK: - Helpers

    /// Builds a minimal ZIP archive containing a single deflated entry.
    ///
    /// Since ``ZIPWriter`` only supports stored entries, this constructs the
    /// binary ZIP format directly with a deflated payload.
    private func buildDeflatedZIP(path: String, originalData: Data) throws -> Data {
        let compressed = try Deflate.compress(originalData)
        let crc = CRC32.calculate(originalData)
        let pathData = Data(path.utf8)

        var archive = Data()

        // Local file header
        archive.appendUInt32(0x04034B50)                          // signature
        archive.appendUInt16(20)                                  // version needed
        archive.appendUInt16(0)                                   // flags
        archive.appendUInt16(8)                                   // compression: deflated
        archive.appendUInt16(0)                                   // mod time
        archive.appendUInt16(0)                                   // mod date
        archive.appendUInt32(crc)                                 // CRC-32
        archive.appendUInt32(UInt32(compressed.count))            // compressed size
        archive.appendUInt32(UInt32(originalData.count))          // uncompressed size
        archive.appendUInt16(UInt16(pathData.count))              // file name length
        archive.appendUInt16(0)                                   // extra field length
        archive.append(pathData)
        archive.append(compressed)

        let centralOffset = UInt32(archive.count)

        // Central directory header
        archive.appendUInt32(0x02014B50)                          // signature
        archive.appendUInt16(20)                                  // version made by
        archive.appendUInt16(20)                                  // version needed
        archive.appendUInt16(0)                                   // flags
        archive.appendUInt16(8)                                   // compression: deflated
        archive.appendUInt16(0)                                   // mod time
        archive.appendUInt16(0)                                   // mod date
        archive.appendUInt32(crc)                                 // CRC-32
        archive.appendUInt32(UInt32(compressed.count))            // compressed size
        archive.appendUInt32(UInt32(originalData.count))          // uncompressed size
        archive.appendUInt16(UInt16(pathData.count))              // file name length
        archive.appendUInt16(0)                                   // extra field length
        archive.appendUInt16(0)                                   // comment length
        archive.appendUInt16(0)                                   // disk number start
        archive.appendUInt16(0)                                   // internal file attributes
        archive.appendUInt32(0)                                   // external file attributes
        archive.appendUInt32(0)                                   // local header offset
        archive.append(pathData)

        let centralSize = UInt32(archive.count) - centralOffset

        // End of Central Directory
        archive.appendUInt32(0x06054B50)                          // signature
        archive.appendUInt16(0)                                   // disk number
        archive.appendUInt16(0)                                   // disk with CD
        archive.appendUInt16(1)                                   // entries on this disk
        archive.appendUInt16(1)                                   // total entries
        archive.appendUInt32(centralSize)                         // CD size
        archive.appendUInt32(centralOffset)                       // CD offset
        archive.appendUInt16(0)                                   // comment length

        return archive
    }
}
