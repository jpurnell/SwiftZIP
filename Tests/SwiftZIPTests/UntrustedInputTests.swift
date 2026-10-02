import Foundation
import Testing
@testable import SwiftZIP

// Every archive here is built byte by byte rather than by `ZIPWriter`, because the
// writer never produces the lies these tests are about: a size field that disagrees
// with the payload, an offset past the end of memory, a count no file could hold.

/// One entry of a hand-built archive. Every size and offset is whatever the test says,
/// not what the payload implies.
private struct CraftedEntry {
    var name = "a"
    var method: UInt16 = 0
    var crc: UInt32 = 0
    var compressedSize: UInt32
    var uncompressedSize: UInt32
    /// `nil` writes the true offset of this entry's local header.
    var localHeaderOffset: UInt32?
    /// Extra field written into the central directory record only.
    var centralExtra = Data()
    var payload = Data()
}

/// The ZIP64 end-of-central-directory fields a test wants to lie about.
private struct CraftedZip64 {
    var entryCount: UInt64
    var centralDirectoryOffset: UInt64?
    /// `nil` writes the true offset of the ZIP64 EOCD record.
    var recordOffset: UInt64?
}

private func craftArchive(_ entries: [CraftedEntry], zip64: CraftedZip64? = nil) -> Data {
    var archive = Data()
    var offsets: [UInt32] = []
    for entry in entries {
        offsets.append(UInt32(archive.count))
        let name = Data(entry.name.utf8)
        archive.appendUInt32(0x04034B50)
        archive.appendUInt16(20)
        archive.appendUInt16(0)
        archive.appendUInt16(entry.method)
        archive.appendUInt16(0)
        archive.appendUInt16(0)
        archive.appendUInt32(entry.crc)
        archive.appendUInt32(entry.compressedSize)
        archive.appendUInt32(entry.uncompressedSize)
        archive.appendUInt16(UInt16(name.count))
        archive.appendUInt16(0)
        archive.append(name)
        archive.append(entry.payload)
    }

    let centralDirectoryOffset = UInt32(archive.count)
    for (entry, offset) in zip(entries, offsets) {
        let name = Data(entry.name.utf8)
        archive.appendUInt32(0x02014B50)
        archive.appendUInt16(20)
        archive.appendUInt16(20)
        archive.appendUInt16(0)
        archive.appendUInt16(entry.method)
        archive.appendUInt16(0)
        archive.appendUInt16(0)
        archive.appendUInt32(entry.crc)
        archive.appendUInt32(entry.compressedSize)
        archive.appendUInt32(entry.uncompressedSize)
        archive.appendUInt16(UInt16(name.count))
        archive.appendUInt16(UInt16(entry.centralExtra.count))
        archive.appendUInt16(0)
        archive.appendUInt16(0)
        archive.appendUInt16(0)
        archive.appendUInt32(0)
        archive.appendUInt32(entry.localHeaderOffset ?? offset)
        archive.append(name)
        archive.append(entry.centralExtra)
    }
    let centralDirectorySize = UInt32(archive.count) - centralDirectoryOffset

    if let zip64 {
        let recordOffset = UInt64(archive.count)
        archive.appendUInt32(0x06064B50)
        archive.appendUInt64(44)
        archive.appendUInt16(45)
        archive.appendUInt16(45)
        archive.appendUInt32(0)
        archive.appendUInt32(0)
        archive.appendUInt64(zip64.entryCount)
        archive.appendUInt64(zip64.entryCount)
        archive.appendUInt64(UInt64(centralDirectorySize))
        archive.appendUInt64(zip64.centralDirectoryOffset ?? UInt64(centralDirectoryOffset))

        archive.appendUInt32(0x07064B50)
        archive.appendUInt32(0)
        archive.appendUInt64(zip64.recordOffset ?? recordOffset)
        archive.appendUInt32(1)
    }

    archive.appendUInt32(0x06054B50)
    archive.appendUInt16(0)
    archive.appendUInt16(0)
    archive.appendUInt16(zip64 == nil ? UInt16(entries.count) : 0xFFFF)
    archive.appendUInt16(zip64 == nil ? UInt16(entries.count) : 0xFFFF)
    archive.appendUInt32(centralDirectorySize)
    archive.appendUInt32(centralDirectoryOffset)
    archive.appendUInt16(0)
    return archive
}

/// A ZIP64 extended-information extra field carrying the given 64-bit values in order.
private func zip64Extra(_ values: [UInt64]) -> Data {
    var extra = Data()
    extra.appendUInt16(0x0001)
    extra.appendUInt16(UInt16(values.count * 8))
    for value in values { extra.appendUInt64(value) }
    return extra
}

/// The smallest valid raw DEFLATE stream: one final stored block of zero bytes.
private let emptyDeflate = Data([0x03, 0x00])

/// Ceilings lifted entirely, so a test can reach the checks that sit behind them.
private let noCeilings = ZIPLimits(
    maxEntryUncompressedSize: .max,
    maxTotalUncompressedSize: .max,
    maxEntryCount: .max
)

private let gibibyte: UInt64 = 1 << 30

@Suite("Untrusted input")
struct UntrustedInputTests {

    // MARK: - Defaults

    @Test("The documented defaults are the values the README promises")
    func defaultLimits() {
        #expect(ZIPLimits.default.maxEntryUncompressedSize == gibibyte)
        #expect(ZIPLimits.default.maxTotalUncompressedSize == 4 * gibibyte)
        #expect(ZIPLimits.default.maxEntryCount == 65_536)
        #expect(ZIPLimits() == ZIPLimits.default)
    }

    // MARK: - Declared sizes

    @Test("A hundred-byte archive declaring a 4 GiB entry is refused before allocation")
    func declaredMultiGiBEntry() {
        let archive = craftArchive([
            CraftedEntry(method: 8, compressedSize: 2, uncompressedSize: 0xFFFF_FFF0,
                         payload: emptyDeflate)
        ])
        #expect(archive.count < 128)
        #expect(throws: ZIPError.limitExceeded(.entryUncompressedSize,
                                               value: 0xFFFF_FFF0, maximum: gibibyte)) {
            _ = try ZIPReader.read(from: archive)
        }
        #expect(throws: ZIPError.limitExceeded(.entryUncompressedSize,
                                               value: 0xFFFF_FFF0, maximum: gibibyte)) {
            _ = try ZIPReader.readEntry(named: "a", from: archive)
        }
    }

    @Test("Deflate cannot expand past 1032:1, so a size beyond that is a lie")
    func deflateExpansionBound() {
        // 2 compressed bytes can yield at most 2,064; declaring 2,065 is impossible.
        let impossible = craftArchive([
            CraftedEntry(method: 8, compressedSize: 2, uncompressedSize: 2_065,
                         payload: emptyDeflate)
        ])
        #expect(throws: ZIPError.malformedHeader) {
            _ = try ZIPReader.read(from: impossible, limits: noCeilings)
        }
        // With the ceilings lifted the 4 GiB claim still fails, on the ratio alone.
        let huge = craftArchive([
            CraftedEntry(method: 8, compressedSize: 2, uncompressedSize: 0xFFFF_FFF0,
                         payload: emptyDeflate)
        ])
        #expect(throws: ZIPError.malformedHeader) {
            _ = try ZIPReader.read(from: huge, limits: noCeilings)
        }
    }

    @Test("A stored entry whose two sizes disagree is malformed")
    func storedSizesDisagree() {
        let payload = Data("hello".utf8)
        let archive = craftArchive([
            CraftedEntry(crc: CRC32.calculate(payload), compressedSize: 5,
                         uncompressedSize: 1_000, payload: payload)
        ])
        #expect(throws: ZIPError.malformedHeader) {
            _ = try ZIPReader.read(from: archive)
        }
    }

    @Test("A per-entry limit set by the caller is enforced against the declared size")
    func callerEntryLimit() throws {
        let archive = try ZIPWriter.write(entries: [
            ZIPEntry(path: "a.bin", data: Data(repeating: 7, count: 100))
        ])
        let limits = ZIPLimits(maxEntryUncompressedSize: 99)
        #expect(throws: ZIPError.limitExceeded(.entryUncompressedSize, value: 100, maximum: 99)) {
            _ = try ZIPReader.read(from: archive, limits: limits)
        }
        let atLimit = try ZIPReader.read(from: archive,
                                         limits: ZIPLimits(maxEntryUncompressedSize: 100))
        #expect(atLimit.map(\.data) == [Data(repeating: 7, count: 100)])
    }

    @Test("The total across entries is limited, not just each entry")
    func totalSizeLimit() throws {
        let entries = (0..<5).map { index in
            ZIPEntry(path: "e\(index).bin", data: Data(repeating: UInt8(index), count: 100))
        }
        let archive = try ZIPWriter.write(entries: entries)
        let limits = ZIPLimits(maxTotalUncompressedSize: 400)
        #expect(throws: ZIPError.limitExceeded(.totalUncompressedSize, value: 500, maximum: 400)) {
            _ = try ZIPReader.read(from: archive, limits: limits)
        }
        let atLimit = try ZIPReader.read(from: archive,
                                         limits: ZIPLimits(maxTotalUncompressedSize: 500))
        #expect(contents(atLimit) == contents(entries))
    }

    @Test("The entry count is limited before any record is read")
    func entryCountLimit() throws {
        let entries = (0..<5).map { ZIPEntry(path: "e\($0)", data: Data()) }
        let archive = try ZIPWriter.write(entries: entries)
        let limits = ZIPLimits(maxEntryCount: 4)
        let expected = ZIPError.limitExceeded(.entryCount, value: 5, maximum: 4)
        #expect(throws: expected) { _ = try ZIPReader.read(from: archive, limits: limits) }
        #expect(throws: expected) { _ = try ZIPReader.listEntries(in: archive, limits: limits) }
        #expect(throws: expected) {
            _ = try ZIPReader.readEntry(named: "e0", from: archive, limits: limits)
        }
    }

    @Test("A ZIP64 count no file could hold is refused, not reserved")
    func zip64ImpossibleEntryCount() {
        let archive = craftArchive([], zip64: CraftedZip64(entryCount: 1 << 40))
        #expect(throws: ZIPError.limitExceeded(.entryCount, value: 1 << 40, maximum: 65_536)) {
            _ = try ZIPReader.read(from: archive)
        }
        // Without the ceiling, the count still cannot fit in the bytes that follow.
        #expect(throws: ZIPError.truncated) {
            _ = try ZIPReader.read(from: archive, limits: noCeilings)
        }
    }

    // MARK: - Integers that do not fit

    @Test("ZIP64 sizes and offset of 0xFFFFFFFFFFFFFFFF throw instead of trapping")
    func zip64AllOnes() {
        let archive = craftArchive([
            CraftedEntry(compressedSize: 0xFFFF_FFFF, uncompressedSize: 0xFFFF_FFFF,
                         localHeaderOffset: 0xFFFF_FFFF,
                         centralExtra: zip64Extra([.max, .max, .max]))
        ])
        #expect(throws: ZIPError.limitExceeded(.entryUncompressedSize,
                                               value: .max, maximum: gibibyte)) {
            _ = try ZIPReader.read(from: archive)
        }
        #expect(throws: ZIPError.malformedHeader) {
            _ = try ZIPReader.read(from: archive, limits: noCeilings)
        }
    }

    @Test("A ZIP64 local-header offset past Int.max throws instead of trapping")
    func zip64HugeOffset() {
        let payload = Data("x".utf8)
        let archive = craftArchive([
            CraftedEntry(crc: CRC32.calculate(payload), compressedSize: 1,
                         uncompressedSize: 1, localHeaderOffset: 0xFFFF_FFFF,
                         centralExtra: zip64Extra([1 << 63]), payload: payload)
        ])
        #expect(throws: ZIPError.malformedHeader) { _ = try ZIPReader.read(from: archive) }
    }

    @Test("A ZIP64 compressed size past Int.max throws instead of trapping")
    func zip64HugeCompressedSize() {
        // Only the compressed size is escaped, so a huge value cannot be caught by the
        // per-entry ceiling, which looks at the uncompressed size.
        let archive = craftArchive([
            CraftedEntry(method: 8, compressedSize: 0xFFFF_FFFF, uncompressedSize: 0,
                         centralExtra: zip64Extra([.max]), payload: emptyDeflate)
        ])
        #expect(throws: ZIPError.malformedHeader) { _ = try ZIPReader.read(from: archive) }
    }

    @Test("ZIP64 directory fields of 0xFFFFFFFFFFFFFFFF throw instead of trapping")
    func zip64DirectoryAllOnes() {
        let badOffset = craftArchive([], zip64: CraftedZip64(entryCount: 0,
                                                             centralDirectoryOffset: .max))
        #expect(throws: ZIPError.malformedHeader) { _ = try ZIPReader.read(from: badOffset) }

        let badCount = craftArchive([], zip64: CraftedZip64(entryCount: .max))
        #expect(throws: ZIPError.malformedHeader) {
            _ = try ZIPReader.read(from: badCount, limits: noCeilings)
        }
    }

    @Test("A ZIP64 locator pointing past Int.max falls back to the standard record")
    func zip64LocatorAllOnes() throws {
        let payload = Data("ok".utf8)
        let archive = craftArchive(
            [CraftedEntry(crc: CRC32.calculate(payload), compressedSize: 2,
                          uncompressedSize: 2, payload: payload)],
            zip64: CraftedZip64(entryCount: 1, recordOffset: .max)
        )
        // The standard EOCD carries the 0xFFFF marker, so without a ZIP64 record there
        // is no count to trust: reading must fail cleanly, not trap on `offset + 56`.
        #expect(throws: ZIPError.truncated) { _ = try ZIPReader.read(from: archive) }
    }

    @Test("Every single-byte corruption of a valid archive throws or reads; none traps")
    func singleByteCorruptionNeverTraps() throws {
        let original = try ZIPWriter.write(entries: [
            ZIPEntry(path: "a.txt", data: Data(repeating: 0x61, count: 300), method: .deflated),
            ZIPEntry(path: "b.txt", data: Data("stored".utf8)),
        ])
        var outcomes = 0
        for position in original.indices {
            for value: UInt8 in [0x00, 0x7F, 0xFF] {
                var mutated = original
                mutated[position] = value
                do {
                    _ = try ZIPReader.read(from: mutated)
                } catch is ZIPError {
                    // A clean throw is the outcome under test.
                }
                outcomes += 1
            }
        }
        #expect(outcomes == original.count * 3)
    }

    // MARK: - Happy path

    @Test("Archives from ZIPWriter still round-trip under the default limits")
    func happyPathRoundTrips() throws {
        let entries = [
            ZIPEntry(path: "stored.txt", data: Data("stored".utf8)),
            ZIPEntry(path: "deflated.txt", data: Data(repeating: 0x41, count: 50_000),
                     method: .deflated),
            ZIPEntry.directory("dir/"),
        ]
        let archive = try ZIPWriter.write(entries: entries)
        #expect(contents(try ZIPReader.read(from: archive)) == contents(entries))
        #expect(contents(try ZIPReader.read(from: archive, limits: .default)) == contents(entries))
        let single = try #require(try ZIPReader.readEntry(named: "deflated.txt", from: archive))
        #expect(contents([single]) == contents([entries[1]]))
        #expect(try ZIPReader.listEntries(in: archive) == entries.map(\.path))
    }

    @Test("A slice of a larger buffer reads the same as a fresh copy")
    func sliceReads() throws {
        let entries = [ZIPEntry(path: "a.txt", data: Data("in a slice".utf8))]
        let archive = try ZIPWriter.write(entries: entries)
        let padded = Data([0xAA, 0xBB, 0xCC]) + archive
        let slice = padded[3...]
        #expect(slice.startIndex == 3)
        #expect(contents(try ZIPReader.read(from: slice)) == contents(entries))
        #expect(try ZIPReader.listEntries(in: slice) == ["a.txt"])
        let single = try #require(try ZIPReader.readEntry(named: "a.txt", from: slice))
        #expect(contents([single]) == contents(entries))
    }

    // MARK: - gzip

    @Test("A 20-byte gzip claiming a 4 GiB ISIZE is refused before allocation")
    func gzipHugeSizeHint() {
        var bytes: [UInt8] = [0x1F, 0x8B, 0x08, 0x00, 0, 0, 0, 0, 0x00, 0xFF]
        bytes += [0x03, 0x00]                  // empty DEFLATE stream
        bytes += [0x00, 0x00, 0x00, 0x00]      // CRC-32
        bytes += [0xFF, 0xFF, 0xFF, 0xFF]      // ISIZE
        let member = Data(bytes)
        #expect(throws: ZIPError.limitExceeded(.entryUncompressedSize,
                                               value: 0xFFFF_FFFF, maximum: gibibyte)) {
            _ = try GzipMember.decompress(member)
        }
        #expect(throws: ZIPError.malformedHeader) {
            _ = try GzipMember.decompress(member, limit: .max)
        }
    }

    @Test("A gzip member is held to the caller's limit")
    func gzipCallerLimit() throws {
        let member = try gzipFixture("no-name")
        let size = UInt64("hello, concordance\nsecond line\n".utf8.count)
        #expect(throws: ZIPError.limitExceeded(.entryUncompressedSize,
                                               value: size, maximum: size - 1)) {
            _ = try GzipMember.decompress(member, limit: size - 1)
        }
        let out = try GzipMember.decompress(member, limit: size)
        #expect(String(decoding: out, as: UTF8.self) == "hello, concordance\nsecond line\n")
    }

    // MARK: - zlib

    @Test("A zlib stream stops at the caller's limit, one byte past it")
    func zlibOutputCeiling() throws {
        let stream = try zlibFixture("large")
        #expect(throws: ZIPError.limitExceeded(.entryUncompressedSize, value: 1_001, maximum: 1_000)) {
            _ = try ZlibStream.inflate(stream, limit: 1_000)
        }
        // The limit is enforced across chunks, not just within the first one.
        #expect(throws: ZIPError.limitExceeded(.entryUncompressedSize,
                                               value: 1_440_000, maximum: 1_439_999)) {
            _ = try ZlibStream.inflate(stream, limit: 1_439_999)
        }
        #expect(try ZlibStream.inflate(stream, limit: 1_440_000).count == 1_440_000)
    }

    // MARK: - Fixtures

    private func gzipFixture(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "gz",
                                          subdirectory: "Fixtures/gzip") else {
            throw FixtureMissing()
        }
        return try Data(contentsOf: url)
    }

    private func zlibFixture(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "zlib",
                                          subdirectory: "Fixtures/zlib") else {
            throw FixtureMissing()
        }
        return try Data(contentsOf: url)
    }
}

private struct FixtureMissing: Error {}

/// What a round trip must preserve. Dates are left out: the writer stamps "now" on an
/// entry that has none, so whole-entry equality would compare clocks, not archives.
private struct Contents: Equatable {
    let path: String
    let data: Data
    let method: CompressionMethod
}

private func contents(_ entries: [ZIPEntry]) -> [Contents] {
    entries.map { Contents(path: $0.path, data: $0.data, method: $0.method) }
}
