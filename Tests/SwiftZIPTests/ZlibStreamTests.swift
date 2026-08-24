import Foundation
import Testing
@testable import SwiftZIP

private enum ZlibFixture: Error { case missing }

/// Fixtures come from Python's `zlib`, never from our own writer: a round-trip against
/// ourselves would pass even if our reading of RFC 1950 were wrong.
private func fixture(_ name: String) throws -> Data {
    guard let url = Bundle.module.url(forResource: name, withExtension: "zlib",
                                      subdirectory: "Fixtures/zlib") else {
        throw ZlibFixture.missing
    }
    return try Data(contentsOf: url)
}

@Suite("Zlib-wrapped streams")
struct ZlibStreamTests {

    @Test("A zlib stream inflates without the caller knowing the output size")
    func inflatesWithoutKnownSize() throws {
        // The existing `Deflate` path requires `uncompressedSize` up front, because a ZIP
        // entry's central directory carries it. A bare zlib stream carries no such field,
        // and the `.itl` case decodes 81 MB to 514 MB — a size nothing declares.
        let out = try ZlibStream.inflate(try fixture("small"))
        #expect(String(decoding: out, as: UTF8.self) == "hello, concordance\nsecond line\n")
    }

    @Test("Output far larger than any first guess is returned whole")
    func growsBeyondTheInitialBuffer() throws {
        let out = try ZlibStream.inflate(try fixture("large"))
        #expect(out.count == 1_440_000)
        #expect(String(decoding: out.prefix(12), as: UTF8.self) == "concordance ")
    }

    @Test("Multi-byte UTF-8 survives byte-for-byte")
    func unicodeSurvives() throws {
        let out = try ZlibStream.inflate(try fixture("unicode"))
        #expect(String(decoding: out, as: UTF8.self) == "café — naïve — 🎵\n")
    }

    @Test("Corruption is DETECTED, not returned")
    func corruptionIsDetected() throws {
        // zlib carries an Adler-32 checksum; a decompressor that cannot detect corruption
        // is worse than none, because it returns plausible garbage.
        var caught = false
        do { _ = try ZlibStream.inflate(try fixture("corrupt")) } catch { caught = true }
        #expect(caught)
    }

    @Test("A raw deflate stream is NOT mistaken for a zlib one")
    func rawDeflateIsRejected() {
        // ZIP entries are raw deflate with no wrapper. Accepting one here would silently
        // read the first two payload bytes as a header.
        let raw = Data([0x4B, 0x4C, 0x4A, 0x4E, 0x49, 0x4D, 0x4B, 0x07, 0x00])
        #expect(throws: (any Error).self) { _ = try ZlibStream.inflate(raw) }
    }

    @Test("Empty and truncated input are reported, never trapped")
    func emptyAndTruncatedAreReported() {
        #expect(throws: (any Error).self) { _ = try ZlibStream.inflate(Data()) }
        #expect(throws: (any Error).self) { _ = try ZlibStream.inflate(Data([0x78])) }
        #expect(throws: (any Error).self) { _ = try ZlibStream.inflate(Data([0x78, 0x9C])) }
    }

    @Test("Arbitrary bytes never trap", arguments: [
        Data(), Data([0x78]), Data([0x78, 0x9C]), Data([0x78, 0x9C, 0x00]),
        Data(repeating: 0x78, count: 200), Data(repeating: 0xFF, count: 64)
    ])
    func neverTraps(payload: Data) {
        _ = try? ZlibStream.inflate(payload)
        #expect(Bool(true))
    }

    @Test("isZlib recognises the wrapper and rejects everything else")
    func headerDetection() throws {
        #expect(ZlibStream.isZlib(try fixture("small")))
        #expect(ZlibStream.isZlib(try fixture("large")), "level 9 uses 78 DA, still zlib")
        #expect(!ZlibStream.isZlib(Data([0x1F, 0x8B])), "that is gzip")
        #expect(!ZlibStream.isZlib(Data([0x50, 0x4B])), "that is a ZIP")
        #expect(!ZlibStream.isZlib(Data()))
    }
}
