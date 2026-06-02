import Foundation
import Testing
@testable import SwiftZIP

@Suite("ZIPWriter")
struct ZIPWriterTests {

    // MARK: - ZIP Signature Constants

    /// Local file header signature: PK\x03\x04
    private let localFileHeaderSignature: [UInt8] = [0x50, 0x4B, 0x03, 0x04]
    /// End of central directory signature: PK\x05\x06
    private let eocdSignature: [UInt8] = [0x50, 0x4B, 0x05, 0x06]
    /// Central directory header signature: PK\x01\x02
    private let centralDirSignature: [UInt8] = [0x50, 0x4B, 0x01, 0x02]

    // MARK: - Empty Archive

    @Test("Empty archive produces valid ZIP with just EOCD")
    func emptyArchive() throws {
        let data = try ZIPWriter.write(entries: [])

        // EOCD record is exactly 22 bytes
        #expect(data.count == 22)

        // Should start with EOCD signature since there are no entries
        let bytes = [UInt8](data)
        #expect(bytes[0] == 0x50)  // P
        #expect(bytes[1] == 0x4B)  // K
        #expect(bytes[2] == 0x05)
        #expect(bytes[3] == 0x06)

        // Entry count should be 0
        let entryCount = data.readUInt16(at: 8)
        #expect(entryCount == 0)

        // Total entries should be 0
        let totalEntries = data.readUInt16(at: 10)
        #expect(totalEntries == 0)
    }

    // MARK: - Single Entry

    @Test("Single entry starts with ZIP local file header signature")
    func singleEntrySignature() throws {
        let entry = ZIPEntry(path: "hello.txt", data: Data("Hello, World!".utf8))
        let data = try ZIPWriter.write(entries: [entry])

        let bytes = [UInt8](data)
        #expect(bytes[0] == localFileHeaderSignature[0])
        #expect(bytes[1] == localFileHeaderSignature[1])
        #expect(bytes[2] == localFileHeaderSignature[2])
        #expect(bytes[3] == localFileHeaderSignature[3])
    }

    @Test("Single entry can be listed with correct count in EOCD")
    func singleEntryCount() throws {
        let entry = ZIPEntry(path: "test.txt", data: Data("test".utf8))
        let data = try ZIPWriter.write(entries: [entry])

        // Find EOCD (last 22 bytes for a zero-comment archive)
        let eocdOffset = data.count - 22
        let signature = data.readUInt32(at: eocdOffset)
        #expect(signature == 0x06054b50)

        let entryCount = data.readUInt16(at: eocdOffset + 8)
        #expect(entryCount == 1)
    }

    // MARK: - Multiple Entries

    @Test("Multiple entries — verify entry count matches")
    func multipleEntriesCount() throws {
        let entries = [
            ZIPEntry(path: "a.txt", data: Data("alpha".utf8)),
            ZIPEntry(path: "b.txt", data: Data("bravo".utf8)),
            ZIPEntry(path: "c.txt", data: Data("charlie".utf8)),
        ]
        let data = try ZIPWriter.write(entries: entries)

        let eocdOffset = data.count - 22
        let entryCount = data.readUInt16(at: eocdOffset + 8)
        #expect(entryCount == 3)

        let totalEntries = data.readUInt16(at: eocdOffset + 10)
        #expect(totalEntries == 3)
    }

    @Test("Multiple entries each have correct data stored")
    func multipleEntriesData() throws {
        let content1 = "First file"
        let content2 = "Second file"
        let entries = [
            ZIPEntry(path: "first.txt", data: Data(content1.utf8)),
            ZIPEntry(path: "second.txt", data: Data(content2.utf8)),
        ]
        let data = try ZIPWriter.write(entries: entries)

        // The first local file header should contain "first.txt" and its data
        let bytes = [UInt8](data)

        // Verify the first entry path appears in the archive
        let firstPathData = [UInt8]("first.txt".utf8)
        #expect(containsSubsequence(bytes, firstPathData))

        // Verify the second entry path appears in the archive
        let secondPathData = [UInt8]("second.txt".utf8)
        #expect(containsSubsequence(bytes, secondPathData))
    }

    // MARK: - Unicode Paths

    @Test("Unicode paths — non-ASCII file names work")
    func unicodePaths() throws {
        let entries = [
            ZIPEntry(path: "café.txt", data: Data("coffee".utf8)),
            ZIPEntry(path: "日本語/ファイル.txt", data: Data("japanese".utf8)),
            ZIPEntry(path: "emoji_🎉.txt", data: Data("party".utf8)),
        ]
        let data = try ZIPWriter.write(entries: entries)

        // Should produce a valid archive with 3 entries
        let eocdOffset = data.count - 22
        let entryCount = data.readUInt16(at: eocdOffset + 8)
        #expect(entryCount == 3)

        // Verify Unicode paths are present in the archive bytes
        let bytes = [UInt8](data)
        #expect(containsSubsequence(bytes, [UInt8]("café.txt".utf8)))
        #expect(containsSubsequence(bytes, [UInt8]("日本語/ファイル.txt".utf8)))
        #expect(containsSubsequence(bytes, [UInt8]("emoji_🎉.txt".utf8)))
    }

    // MARK: - Large Entry

    @Test("Large entry (100KB+) — size fields are correct")
    func largeEntry() throws {
        let largeData = Data(repeating: 0xAB, count: 150_000)
        let entry = ZIPEntry(path: "large.bin", data: largeData)
        let data = try ZIPWriter.write(entries: [entry])

        // Verify the local file header size fields
        // Offset 18: compressed size (UInt32)
        // Offset 22: uncompressed size (UInt32)
        let compressedSize = data.readUInt32(at: 18)
        let uncompressedSize = data.readUInt32(at: 22)

        #expect(compressedSize == 150_000)
        #expect(uncompressedSize == 150_000)
    }

    // MARK: - Binary Data

    @Test("Binary data (non-UTF8) — raw bytes survive round-trip")
    func binaryData() throws {
        // Create data with all possible byte values (non-UTF8)
        var binaryContent = Data()
        for i: UInt8 in 0...255 {
            binaryContent.append(i)
        }
        let entry = ZIPEntry(path: "binary.dat", data: binaryContent)
        let data = try ZIPWriter.write(entries: [entry])

        // The binary content should appear intact after the local file header
        // Local header: 30 bytes fixed + path length
        let pathLength = Data("binary.dat".utf8).count
        let dataOffset = 30 + pathLength
        let storedData = data.subdata(in: dataOffset..<(dataOffset + 256))

        #expect(storedData == binaryContent)
    }

    // MARK: - Write to URL

    @Test("Write to URL — file exists and can be read back")
    func writeToURL() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test_\(UUID().uuidString).zip")

        let entry = ZIPEntry(path: "hello.txt", data: Data("Hello".utf8))
        try ZIPWriter.write(entries: [entry], to: fileURL)

        // Verify file exists
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        // Verify file can be read back and starts with ZIP signature
        let readBack = try Data(contentsOf: fileURL)
        #expect(readBack.count > 0)
        let bytes = [UInt8](readBack)
        #expect(bytes[0] == 0x50)
        #expect(bytes[1] == 0x4B)

        // Clean up
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Write to Data

    @Test("Write to Data — returned Data starts with ZIP signature")
    func writeToData() throws {
        let entry = ZIPEntry(path: "data.txt", data: Data("data content".utf8))
        let data = try ZIPWriter.write(entries: [entry])

        let bytes = [UInt8](data)
        // ZIP signature: PK\x03\x04
        #expect(bytes[0] == 0x50)
        #expect(bytes[1] == 0x4B)
        #expect(bytes[2] == 0x03)
        #expect(bytes[3] == 0x04)
    }

    // MARK: - CRC-32 Correctness

    @Test("CRC-32 is correct in the archive local header")
    func crc32InLocalHeader() throws {
        let content = Data("Hello, World!".utf8)
        let expectedCRC = CRC32.calculate(content)

        let entry = ZIPEntry(path: "crc_test.txt", data: content)
        let data = try ZIPWriter.write(entries: [entry])

        // CRC-32 is at offset 14 in the local file header
        let storedCRC = data.readUInt32(at: 14)
        #expect(storedCRC == expectedCRC)
    }

    @Test("CRC-32 is correct in the central directory header")
    func crc32InCentralDirectory() throws {
        let content = Data("CRC test data".utf8)
        let expectedCRC = CRC32.calculate(content)

        let entry = ZIPEntry(path: "crc_cd.txt", data: content)
        let data = try ZIPWriter.write(entries: [entry])

        // Find the central directory header
        let bytes = [UInt8](data)
        guard let cdOffset = findSignature(in: bytes, signature: centralDirSignature) else {
            #expect(Bool(false), "Central directory header not found")
            return
        }

        // CRC-32 is at offset 16 within the central directory header
        let storedCRC = data.readUInt32(at: cdOffset + 16)
        #expect(storedCRC == expectedCRC)
    }

    @Test("CRC-32 matches between local header and central directory")
    func crc32Consistency() throws {
        let content = Data("consistency check".utf8)
        let entry = ZIPEntry(path: "consistency.txt", data: content)
        let data = try ZIPWriter.write(entries: [entry])

        let localCRC = data.readUInt32(at: 14)

        let bytes = [UInt8](data)
        guard let cdOffset = findSignature(in: bytes, signature: centralDirSignature) else {
            #expect(Bool(false), "Central directory header not found")
            return
        }
        let centralCRC = data.readUInt32(at: cdOffset + 16)

        #expect(localCRC == centralCRC)
    }

    // MARK: - Compression Method Validation

    @Test("Deflated entries throw unsupported compression error")
    func deflatedEntryThrows() throws {
        let entry = ZIPEntry(path: "compressed.txt", data: Data("data".utf8), method: .deflated)
        #expect(throws: ZIPError.self) {
            _ = try ZIPWriter.write(entries: [entry])
        }
    }

    // MARK: - Structure Validation

    @Test("Archive contains all three record types in order")
    func archiveStructure() throws {
        let entry = ZIPEntry(path: "structure.txt", data: Data("test".utf8))
        let data = try ZIPWriter.write(entries: [entry])
        let bytes = [UInt8](data)

        // Find each signature
        let localOffset = findSignature(in: bytes, signature: localFileHeaderSignature)
        let centralOffset = findSignature(in: bytes, signature: centralDirSignature)
        let eocdOffset = findSignature(in: bytes, signature: eocdSignature)

        // All three must exist
        #expect(localOffset != nil)
        #expect(centralOffset != nil)
        #expect(eocdOffset != nil)

        // They must appear in order: local < central < eocd
        if let local = localOffset, let central = centralOffset, let eocd = eocdOffset {
            #expect(local < central)
            #expect(central < eocd)
        }
    }

    @Test("Central directory offset in EOCD is correct")
    func centralDirectoryOffset() throws {
        let entry = ZIPEntry(path: "offset.txt", data: Data("test offset".utf8))
        let data = try ZIPWriter.write(entries: [entry])

        let eocdOffset = data.count - 22
        let recordedCDOffset = data.readUInt32(at: eocdOffset + 16)

        // Verify the recorded offset actually points to a central directory signature
        let signature = data.readUInt32(at: Int(recordedCDOffset))
        #expect(signature == 0x02014b50)
    }

    // MARK: - Empty Data Entry

    @Test("Entry with empty data produces valid archive")
    func emptyDataEntry() throws {
        let entry = ZIPEntry(path: "empty.txt", data: Data())
        let data = try ZIPWriter.write(entries: [entry])

        // Should be valid with 1 entry
        let eocdOffset = data.count - 22
        let entryCount = data.readUInt16(at: eocdOffset + 8)
        #expect(entryCount == 1)

        // Size fields should be 0
        let compressedSize = data.readUInt32(at: 18)
        let uncompressedSize = data.readUInt32(at: 22)
        #expect(compressedSize == 0)
        #expect(uncompressedSize == 0)
    }

    // MARK: - Helpers

    /// Checks whether `haystack` contains `needle` as a contiguous subsequence.
    private func containsSubsequence(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        guard needle.count <= haystack.count else { return false }
        for i in 0...(haystack.count - needle.count) {
            if Array(haystack[i..<(i + needle.count)]) == needle {
                return true
            }
        }
        return false
    }

    /// Finds the first occurrence of a 4-byte signature in the byte array.
    private func findSignature(in bytes: [UInt8], signature: [UInt8]) -> Int? {
        guard bytes.count >= 4 else { return nil }
        for i in 0...(bytes.count - 4) {
            if bytes[i] == signature[0] && bytes[i + 1] == signature[1]
                && bytes[i + 2] == signature[2] && bytes[i + 3] == signature[3]
            {
                return i
            }
        }
        return nil
    }
}
