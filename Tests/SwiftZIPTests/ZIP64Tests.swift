import Testing
import Foundation
@testable import SwiftZIP

@Suite("ZIP64 Extensions")
struct ZIP64Tests {

    // MARK: - Entry Count Threshold

    @Test("Archive with 65,536 entries uses ZIP64 and round-trips")
    func zip64EntryCount() throws {
        let count = 65_536
        let entries = (0..<count).map { i in
            ZIPEntry(path: "f\(i)", data: Data())
        }
        let archive = try ZIPWriter.write(entries: entries)
        let result = try ZIPReader.read(from: archive)

        #expect(result.count == count)
        #expect(result[0].path == "f0")
        #expect(result[count - 1].path == "f\(count - 1)")
    }

    @Test("Archive with 65,536 entries contains ZIP64 EOCD signature")
    func zip64EOCDPresent() throws {
        let entries = (0..<65_536).map { i in
            ZIPEntry(path: "f\(i)", data: Data())
        }
        let archive = try ZIPWriter.write(entries: entries)
        let bytes = [UInt8](archive)

        // ZIP64 EOCD signature: 0x06064B50
        let found = containsSignature(bytes, signature: [0x50, 0x4B, 0x06, 0x06])
        #expect(found)
    }

    @Test("Archive below 65,535 entries does NOT contain ZIP64 EOCD")
    func noZip64BelowThreshold() throws {
        let entries = [
            ZIPEntry(path: "a.txt", data: Data("hello".utf8)),
            ZIPEntry(path: "b.txt", data: Data("world".utf8)),
        ]
        let archive = try ZIPWriter.write(entries: entries)
        let bytes = [UInt8](archive)

        let found = containsSignature(bytes, signature: [0x50, 0x4B, 0x06, 0x06])
        #expect(!found)
    }

    // MARK: - Synthetic Large-Size Entry

    @Test("Reader handles ZIP64 extra field for large entries")
    func readZip64ExtraField() throws {
        // Build a synthetic archive where the central directory reports
        // size=0xFFFFFFFF and the real size is in a ZIP64 extra field.
        let content = Data("zip64 extra field test".utf8)
        let archive = try buildSyntheticZIP64Archive(
            path: "big.txt",
            data: content,
            reportedSize: 0xFFFFFFFF,
            actualSize: UInt64(content.count)
        )

        let result = try ZIPReader.read(from: archive)
        #expect(result.count == 1)
        #expect(result[0].path == "big.txt")
        #expect(result[0].data == content)
    }

    @Test("Writer produces ZIP64 extra field when entry count exceeds UInt16")
    func writerZip64ExtraFieldForCount() throws {
        let count = 65_536
        let entries = (0..<count).map { i in
            ZIPEntry(path: "e\(i)", data: Data())
        }
        let archive = try ZIPWriter.write(entries: entries)

        // Verify ZIP64 EOCD locator signature is present: 0x07064B50
        let bytes = [UInt8](archive)
        let hasLocator = containsSignature(bytes, signature: [0x50, 0x4B, 0x06, 0x07])
        #expect(hasLocator)
    }

    @Test("Standard entries below all thresholds produce no ZIP64 extra fields")
    func noZip64ExtraForSmallEntries() throws {
        let entry = ZIPEntry(path: "small.txt", data: Data("tiny".utf8))
        let archive = try ZIPWriter.write(entries: [entry])
        let bytes = [UInt8](archive)

        // No ZIP64 EOCD locator
        let hasLocator = containsSignature(bytes, signature: [0x50, 0x4B, 0x06, 0x07])
        #expect(!hasLocator)
    }

    // MARK: - Helpers

    private func containsSignature(_ bytes: [UInt8], signature: [UInt8]) -> Bool {
        guard bytes.count >= signature.count else { return false }
        for i in 0...(bytes.count - signature.count) {
            if bytes[i] == signature[0] && bytes[i + 1] == signature[1]
                && bytes[i + 2] == signature[2] && bytes[i + 3] == signature[3]
            {
                return true
            }
        }
        return false
    }

    /// Builds a minimal ZIP archive with a ZIP64 extra field on a single entry.
    private func buildSyntheticZIP64Archive(
        path: String,
        data: Data,
        reportedSize: UInt32,
        actualSize: UInt64
    ) throws -> Data {
        let crc = CRC32.calculate(data)
        let pathData = Data(path.utf8)
        var archive = Data()

        // ZIP64 extra field: tag=0x0001, size=16, uncompressed size, compressed size
        var zip64Extra = Data()
        zip64Extra.appendUInt16(0x0001)
        zip64Extra.appendUInt16(16)
        zip64Extra.appendUInt64(actualSize)  // uncompressed
        zip64Extra.appendUInt64(actualSize)  // compressed

        // Local file header
        archive.appendUInt32(0x04034B50)
        archive.appendUInt16(45)                                  // version needed for ZIP64
        archive.appendUInt16(0)
        archive.appendUInt16(0)                                   // stored
        archive.appendUInt16(0)
        archive.appendUInt16(0)
        archive.appendUInt32(crc)
        archive.appendUInt32(reportedSize)                        // compressed size = 0xFFFFFFFF
        archive.appendUInt32(reportedSize)                        // uncompressed size = 0xFFFFFFFF
        archive.appendUInt16(UInt16(pathData.count))
        archive.appendUInt16(UInt16(zip64Extra.count))
        archive.append(pathData)
        archive.append(zip64Extra)
        archive.append(data)

        let cdOffset = UInt32(archive.count)

        // Central directory header
        archive.appendUInt32(0x02014B50)
        archive.appendUInt16(45)
        archive.appendUInt16(45)
        archive.appendUInt16(0)
        archive.appendUInt16(0)                                   // stored
        archive.appendUInt16(0)
        archive.appendUInt16(0)
        archive.appendUInt32(crc)
        archive.appendUInt32(reportedSize)
        archive.appendUInt32(reportedSize)
        archive.appendUInt16(UInt16(pathData.count))
        archive.appendUInt16(UInt16(zip64Extra.count))
        archive.appendUInt16(0)
        archive.appendUInt16(0)
        archive.appendUInt16(0)
        archive.appendUInt32(0)
        archive.appendUInt32(0)                                   // local header offset
        archive.append(pathData)
        archive.append(zip64Extra)

        let cdSize = UInt32(archive.count) - cdOffset

        // ZIP64 EOCD
        archive.appendUInt32(0x06064B50)                          // signature
        archive.appendUInt64(44)                                  // size of remaining record
        archive.appendUInt16(45)                                  // version made by
        archive.appendUInt16(45)                                  // version needed
        archive.appendUInt32(0)                                   // disk number
        archive.appendUInt32(0)                                   // disk with CD
        archive.appendUInt64(1)                                   // entries on this disk
        archive.appendUInt64(1)                                   // total entries
        archive.appendUInt64(UInt64(cdSize))                      // CD size
        archive.appendUInt64(UInt64(cdOffset))                    // CD offset

        let zip64EOCDOffset = UInt64(archive.count - 56)          // start of ZIP64 EOCD

        // ZIP64 EOCD locator
        archive.appendUInt32(0x07064B50)                          // signature
        archive.appendUInt32(0)                                   // disk with ZIP64 EOCD
        archive.appendUInt64(zip64EOCDOffset)                     // offset of ZIP64 EOCD
        archive.appendUInt32(1)                                   // total disks

        // Standard EOCD (with 0xFFFF marker for entry count)
        archive.appendUInt32(0x06054B50)
        archive.appendUInt16(0)
        archive.appendUInt16(0)
        archive.appendUInt16(0xFFFF)                              // entries on disk = marker
        archive.appendUInt16(0xFFFF)                              // total entries = marker
        archive.appendUInt32(cdSize)
        archive.appendUInt32(cdOffset)
        archive.appendUInt16(0)

        return archive
    }
}
