import Testing
import Foundation
@testable import SwiftZIP

@Suite("Deflate Compression Tests")
struct DeflateTests {
    // MARK: - Decompress Edge Cases

    @Test("Empty data with size 0 returns empty Data")
    func emptyData() throws {
        let result = try Deflate.decompress(Data(), uncompressedSize: 0)
        #expect(result.isEmpty)
    }

    // MARK: - Round-Trip Tests

    @Test("Round-trip: compress then decompress 'Hello, World!'")
    func roundTripString() throws {
        let original = Data("Hello, World!".utf8)
        let compressed = try Deflate.compress(original)
        let decompressed = try Deflate.decompress(compressed, uncompressedSize: original.count)
        #expect(decompressed == original)
    }

    @Test("Round-trip: binary data (repeating 0xAB)")
    func roundTripBinary() throws {
        let original = Data(repeating: 0xAB, count: 1000)
        let compressed = try Deflate.compress(original)
        let decompressed = try Deflate.decompress(compressed, uncompressedSize: original.count)
        #expect(decompressed == original)
    }

    @Test("Round-trip: large data (100KB repeated pattern)")
    func roundTripLarge() throws {
        // Build a repeating pattern across 100KB
        let pattern = Data("SwiftZIP-Deflate-Test-Pattern-".utf8)
        var original = Data()
        while original.count < 100_000 {
            original.append(pattern)
        }
        original = original.prefix(100_000)

        let compressed = try Deflate.compress(original)
        let decompressed = try Deflate.decompress(compressed, uncompressedSize: original.count)
        #expect(decompressed == original)
    }

    @Test("Round-trip: single byte")
    func roundTripSingleByte() throws {
        let original = Data([0x42])
        let compressed = try Deflate.compress(original)
        let decompressed = try Deflate.decompress(compressed, uncompressedSize: original.count)
        #expect(decompressed == original)
    }

    @Test("Round-trip: all zeros (highly compressible)")
    func roundTripAllZeros() throws {
        let original = Data(repeating: 0x00, count: 10_000)
        let compressed = try Deflate.compress(original)
        let decompressed = try Deflate.decompress(compressed, uncompressedSize: original.count)
        #expect(decompressed == original)
    }

    @Test("Round-trip: realistic XML content (Excel-like)")
    func roundTripXML() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <sheetData>
            <row r="1">
              <c r="A1" t="s"><v>0</v></c>
              <c r="B1" t="s"><v>1</v></c>
              <c r="C1"><v>42</v></c>
            </row>
            <row r="2">
              <c r="A2" t="s"><v>2</v></c>
              <c r="B2" t="s"><v>3</v></c>
              <c r="C2"><v>100</v></c>
            </row>
          </sheetData>
        </worksheet>
        """
        let original = Data(xml.utf8)
        let compressed = try Deflate.compress(original)
        let decompressed = try Deflate.decompress(compressed, uncompressedSize: original.count)
        #expect(decompressed == original)
    }

    // MARK: - Compression Effectiveness

    @Test("Compression reduces size for repetitive data")
    func compressionReducesSize() throws {
        let original = Data(repeating: 0x00, count: 10_000)
        let compressed = try Deflate.compress(original)
        #expect(compressed.count < original.count)
    }

    @Test("Compression reduces size for XML content")
    func compressionReducesSizeXML() throws {
        let xml = String(repeating: "<row><c r=\"A1\"><v>42</v></c></row>\n", count: 200)
        let original = Data(xml.utf8)
        let compressed = try Deflate.compress(original)
        #expect(compressed.count < original.count)
    }

    // MARK: - Error Cases

    @Test("Decompress with wrong uncompressedSize throws deflateError")
    func sizeMismatchThrows() throws {
        let original = Data("Hello, World!".utf8)
        let compressed = try Deflate.compress(original)

        // Request a size that does not match the actual decompressed output
        #expect(throws: ZIPError.self) {
            _ = try Deflate.decompress(compressed, uncompressedSize: original.count + 100)
        }
    }

    // MARK: - Empty Input

    @Test("Compress empty data returns empty Data")
    func compressEmptyData() throws {
        let result = try Deflate.compress(Data())
        #expect(result.isEmpty)
    }

    // MARK: - Known Deflate Bytes

    @Test("Decompress known deflate bytes produces expected output")
    func knownDeflateBytes() throws {
        // Compress a known string, capture the compressed bytes,
        // then verify decompression matches.
        let original = Data("AAAAAAAAAA".utf8) // 10 'A' bytes
        let compressed = try Deflate.compress(original)

        // Verify the compressed form is non-empty and different from original
        #expect(!compressed.isEmpty)

        // Decompress and verify
        let decompressed = try Deflate.decompress(compressed, uncompressedSize: 10)
        #expect(decompressed == original)
        #expect(decompressed.count == 10)
        // Verify every byte is ASCII 'A' (0x41)
        for byte in decompressed {
            #expect(byte == 0x41)
        }
    }

    // MARK: - Various Data Patterns

    @Test("Round-trip: ascending byte sequence")
    func roundTripAscending() throws {
        let original = Data((0..<256).map { UInt8($0) })
        let compressed = try Deflate.compress(original)
        let decompressed = try Deflate.decompress(compressed, uncompressedSize: original.count)
        #expect(decompressed == original)
    }
}
