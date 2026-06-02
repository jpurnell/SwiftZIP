import Foundation
import Testing
@testable import SwiftZIP

@Suite("Round-Trip Tests")
struct RoundTripTests {

    // MARK: - 1. Single Text Entry

    @Test("Single text entry round-trips with matching path and data")
    func singleTextEntry() throws {
        let original = ZIPEntry(path: "hello.txt", data: Data("Hello, World!".utf8))
        let archive = try ZIPWriter.write(entries: [original])
        let result = try ZIPReader.read(from: archive)

        #expect(result.count == 1)
        #expect(result[0].path == original.path)
        #expect(result[0].data == original.data)
    }

    // MARK: - 2. Multiple Entries

    @Test("Five entries with different content all round-trip correctly")
    func multipleEntries() throws {
        let entries = [
            ZIPEntry(path: "alpha.txt", data: Data("Alpha content".utf8)),
            ZIPEntry(path: "beta.txt", data: Data("Beta content here".utf8)),
            ZIPEntry(path: "gamma.bin", data: Data([0x00, 0x01, 0x02, 0x03])),
            ZIPEntry(path: "delta.xml", data: Data("<delta/>".utf8)),
            ZIPEntry(path: "epsilon.txt", data: Data("The fifth entry".utf8)),
        ]
        let archive = try ZIPWriter.write(entries: entries)
        let result = try ZIPReader.read(from: archive)

        #expect(result.count == 5)
        for (original, read) in zip(entries, result) {
            #expect(read.path == original.path)
            #expect(read.data == original.data)
        }
    }

    // MARK: - 3. Empty Data Entry

    @Test("Entry with empty Data() round-trips correctly")
    func emptyDataEntry() throws {
        let original = ZIPEntry(path: "empty.txt", data: Data())
        let archive = try ZIPWriter.write(entries: [original])
        let result = try ZIPReader.read(from: archive)

        #expect(result.count == 1)
        #expect(result[0].path == "empty.txt")
        #expect(result[0].data == Data())
        #expect(result[0].data.isEmpty)
    }

    // MARK: - 4. Binary Data (All 256 Byte Values)

    @Test("Entry with all 256 byte values round-trips intact")
    func binaryDataAllBytes() throws {
        var binaryContent = Data()
        for byte: UInt8 in 0...255 {
            binaryContent.append(byte)
        }
        let original = ZIPEntry(path: "all_bytes.bin", data: binaryContent)
        let archive = try ZIPWriter.write(entries: [original])
        let result = try ZIPReader.read(from: archive)

        #expect(result.count == 1)
        #expect(result[0].data.count == 256)
        #expect(result[0].data == binaryContent)
    }

    // MARK: - 5. Large Entry (500KB)

    @Test("500KB entry round-trips with identical data")
    func largeEntry() throws {
        let largeData = Data(repeating: 0x42, count: 500_000)
        let original = ZIPEntry(path: "large.bin", data: largeData)
        let archive = try ZIPWriter.write(entries: [original])
        let result = try ZIPReader.read(from: archive)

        #expect(result.count == 1)
        #expect(result[0].data.count == 500_000)
        #expect(result[0].data == largeData)
    }

    // MARK: - 6. Many Small Entries

    @Test("100 small entries all round-trip correctly")
    func manySmallEntries() throws {
        let entries = (0..<100).map { i in
            ZIPEntry(path: "file_\(i).txt", data: Data("Content \(i)".utf8))
        }
        let archive = try ZIPWriter.write(entries: entries)
        let result = try ZIPReader.read(from: archive)

        #expect(result.count == 100)
        for (original, read) in zip(entries, result) {
            #expect(read.path == original.path)
            #expect(read.data == original.data)
        }
    }

    // MARK: - 7. Unicode Paths

    @Test("Entries with accented, CJK, and emoji paths round-trip correctly")
    func unicodePaths() throws {
        let entries = [
            ZIPEntry(path: "café.txt", data: Data("coffee".utf8)),
            ZIPEntry(path: "résumé.doc", data: Data("resume".utf8)),
            ZIPEntry(path: "日本語.txt", data: Data("japanese".utf8)),
            ZIPEntry(path: "中文文件.txt", data: Data("chinese".utf8)),
            ZIPEntry(path: "🎉🚀📦.txt", data: Data("emoji party".utf8)),
        ]
        let archive = try ZIPWriter.write(entries: entries)
        let result = try ZIPReader.read(from: archive)

        #expect(result.count == 5)
        for (original, read) in zip(entries, result) {
            #expect(read.path == original.path)
            #expect(read.data == original.data)
        }
    }

    // MARK: - 8. Long Path

    @Test("Entry with a 300-character path round-trips correctly")
    func longPath() throws {
        let longName = String(repeating: "a", count: 290) + ".txt"
        #expect(longName.count > 255)

        let original = ZIPEntry(path: longName, data: Data("long path data".utf8))
        let archive = try ZIPWriter.write(entries: [original])
        let result = try ZIPReader.read(from: archive)

        #expect(result.count == 1)
        #expect(result[0].path == longName)
        #expect(result[0].data == Data("long path data".utf8))
    }

    // MARK: - 9. Nested Paths

    @Test("Entries with nested directory paths round-trip correctly")
    func nestedPaths() throws {
        let entries = [
            ZIPEntry(path: "a/b/c/d.txt", data: Data("deeply nested".utf8)),
            ZIPEntry(path: "foo/bar/baz.xml", data: Data("<baz/>".utf8)),
            ZIPEntry(path: "root/level1/level2/level3/file.dat", data: Data([0xAA, 0xBB])),
        ]
        let archive = try ZIPWriter.write(entries: entries)
        let result = try ZIPReader.read(from: archive)

        #expect(result.count == 3)
        for (original, read) in zip(entries, result) {
            #expect(read.path == original.path)
            #expect(read.data == original.data)
        }
    }

    // MARK: - 10. XML Content

    @Test("Realistic XML content round-trips without corruption")
    func xmlContent() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <root>
            <item id="1">First item</item>
            <item id="2">Second item</item>
            <nested>
                <child attr="value">Content &amp; more</child>
            </nested>
        </root>
        """
        let original = ZIPEntry(path: "data.xml", data: Data(xml.utf8))
        let archive = try ZIPWriter.write(entries: [original])
        let result = try ZIPReader.read(from: archive)

        #expect(result.count == 1)
        #expect(result[0].path == "data.xml")
        #expect(result[0].data == Data(xml.utf8))

        let readString = String(decoding: result[0].data, as: UTF8.self)
        #expect(readString.contains("<?xml version=\"1.0\""))
        #expect(readString.contains("Content &amp; more"))
    }

    // MARK: - 11. Whitespace in Paths

    @Test("Paths with spaces round-trip correctly")
    func whitespaceInPaths() throws {
        let entries = [
            ZIPEntry(path: "my file.txt", data: Data("spaced name".utf8)),
            ZIPEntry(path: "path with spaces/data.xml", data: Data("<spaced/>".utf8)),
            ZIPEntry(path: "  leading.txt", data: Data("leading spaces".utf8)),
        ]
        let archive = try ZIPWriter.write(entries: entries)
        let result = try ZIPReader.read(from: archive)

        #expect(result.count == 3)
        for (original, read) in zip(entries, result) {
            #expect(read.path == original.path)
            #expect(read.data == original.data)
        }
    }

    // MARK: - 12. Entry Count Preserved

    @Test("listEntries returns exactly N paths for N written entries")
    func entryCountPreserved() throws {
        let count = 42
        let entries = (0..<count).map { i in
            ZIPEntry(path: "entry_\(i).txt", data: Data("data \(i)".utf8))
        }
        let archive = try ZIPWriter.write(entries: entries)
        let paths = try ZIPReader.listEntries(in: archive)

        #expect(paths.count == count)
        for i in 0..<count {
            #expect(paths[i] == "entry_\(i).txt")
        }
    }

    // MARK: - 13. Read Specific Entry

    @Test("readEntry(named:) finds each of 10 entries individually")
    func readSpecificEntry() throws {
        let entries = (0..<10).map { i in
            ZIPEntry(path: "item_\(i).dat", data: Data("payload_\(i)".utf8))
        }
        let archive = try ZIPWriter.write(entries: entries)

        for i in 0..<10 {
            let name = "item_\(i).dat"
            let found = try ZIPReader.readEntry(named: name, from: archive)
            #expect(found != nil)
            #expect(found?.path == name)
            #expect(found?.data == Data("payload_\(i)".utf8))
        }
    }

    // MARK: - 14. Data Integrity (CRC-32 Verification)

    @Test("CRC-32 of read-back data matches CRC-32 of original data")
    func dataIntegrityCRC32() throws {
        let entries = [
            ZIPEntry(path: "text.txt", data: Data("Some text content".utf8)),
            ZIPEntry(path: "binary.bin", data: Data(repeating: 0xDE, count: 1024)),
            ZIPEntry(path: "mixed.dat", data: Data([0x00, 0xFF, 0x80, 0x7F, 0x01, 0xFE])),
        ]
        let archive = try ZIPWriter.write(entries: entries)
        let result = try ZIPReader.read(from: archive)

        #expect(result.count == entries.count)
        for (original, read) in zip(entries, result) {
            let originalCRC = CRC32.calculate(original.data)
            let readCRC = CRC32.calculate(read.data)
            #expect(readCRC == originalCRC)
        }
    }

    // MARK: - 15. Double Round-Trip

    @Test("Write, read, write again, read again yields identical data")
    func doubleRoundTrip() throws {
        let entries = [
            ZIPEntry(path: "first.txt", data: Data("First file content".utf8)),
            ZIPEntry(path: "second.bin", data: Data([0xCA, 0xFE, 0xBA, 0xBE])),
            ZIPEntry(path: "third/nested.xml", data: Data("<root>data</root>".utf8)),
        ]

        // First round-trip: write -> read
        let archive1 = try ZIPWriter.write(entries: entries)
        let result1 = try ZIPReader.read(from: archive1)

        #expect(result1.count == entries.count)

        // Second round-trip: write read entries -> read again
        let archive2 = try ZIPWriter.write(entries: result1)
        let result2 = try ZIPReader.read(from: archive2)

        #expect(result2.count == entries.count)

        // Verify final result matches the original entries
        for (original, final) in zip(entries, result2) {
            #expect(final.path == original.path)
            #expect(final.data == original.data)
        }
    }
}
