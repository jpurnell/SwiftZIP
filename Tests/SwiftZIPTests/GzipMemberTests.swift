import Foundation
import Testing
@testable import SwiftZIP

/// Creates a scratch directory, validated before use.
///
/// The name is generated, so the resulting path is checked to be an absolute path
/// containing no traversal components and rooted in the temporary directory — a
/// dynamic path handed to `FileManager` without that check is CWE-22.
private func scratchDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory.standardizedFileURL
    let candidate = root.appendingPathComponent("swiftzip-\(UUID().uuidString)")
        .standardizedFileURL
    guard candidate.path.hasPrefix(root.path),
          !candidate.pathComponents.contains("..") else {
        throw ScratchFailure.unsafePath
    }
    try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
    return candidate
}

private enum ScratchFailure: Error { case unsafePath, missingFixture }

/// Fixtures come from the **system `gzip`**, never from our own writer: a round-trip
/// against ourselves would pass even if our reading of RFC 1952 were wrong.
///
/// They are committed rather than generated at run time. Generating them would mean
/// spawning `/usr/bin/gzip` on every run — an unbounded child process in a test — and
/// would make the suite depend on whichever gzip the host happens to ship.
private func fixture(_ name: String) throws -> Data {
    guard let url = Bundle.module.url(
        forResource: name, withExtension: "gz", subdirectory: "Fixtures/gzip"
    ) else { throw ScratchFailure.missingFixture }
    return try Data(contentsOf: url)
}

/// The exact bytes each fixture was compressed from.
private enum Original {
    static let plain = "hello, concordance\nsecond line\n"
    static let unicode = "café — naïve — 🎵\n"
    static let large = String(repeating: "concordance ", count: 120_000)
}

@Test("A system-produced member round-trips")
func roundTrips() throws {
    let out = try GzipMember.decompress(try fixture("no-name"))
    #expect(String(decoding: out, as: UTF8.self) == Original.plain)
}

@Test("Multi-byte UTF-8 survives byte-for-byte")
func unicodeRoundTrips() throws {
    let out = try GzipMember.decompress(try fixture("unicode"))
    #expect(String(decoding: out, as: UTF8.self) == Original.unicode)
}

@Test("Both header variants read: `gzip -n` omits FNAME, plain `gzip` includes it")
func headerVariants() throws {
    let withoutName = try GzipMember.decompress(try fixture("no-name"))
    let withName = try GzipMember.decompress(try fixture("with-name"))
    #expect(String(decoding: withoutName, as: UTF8.self) == Original.plain)
    #expect(String(decoding: withName, as: UTF8.self) == Original.plain,
            "a fixed 10-byte header would silently misread this one")
}

@Test("Content far larger than any buffer guess decodes completely")
func largeContent() throws {
    let out = try GzipMember.decompress(try fixture("large"))
    #expect(out.count == Original.large.utf8.count)
    #expect(String(decoding: out, as: UTF8.self) == Original.large)
}

@Test("Corruption is DETECTED, not returned")
func corruptionIsDetected() throws {
    var bytes = [UInt8](try fixture("large"))
    // Damage the payload; leave header and trailer intact so only the CRC can catch it.
    for i in 14..<min(bytes.count - 8, 40) { bytes[i] ^= 0xFF }
    var caught = false
    do { _ = try GzipMember.decompress(Data(bytes)) } catch { caught = true }
    #expect(caught, "a decompressor that cannot detect corruption is worse than none")
}

@Test("Non-gzip input is reported")
func rejectsNonGzip() {
    #expect(throws: GzipMember.Failure.notGzip) {
        _ = try GzipMember.decompress(Data(repeating: 0x41, count: 64))
    }
}

@Test("Truncated input is reported")
func rejectsTruncated() {
    #expect(throws: GzipMember.Failure.tooShort) {
        _ = try GzipMember.decompress(Data([0x1F, 0x8B, 0x08, 0x00]))
    }
}

@Test("A header claiming fields past the end is reported")
func rejectsMalformedHeader() throws {
    var bytes = [UInt8](try fixture("no-name"))
    bytes[3] = 0x04                    // claim FEXTRA…
    bytes[10] = 0xFF; bytes[11] = 0xFF // …of 65,535 bytes
    #expect(throws: GzipMember.Failure.malformedHeader) {
        _ = try GzipMember.decompress(Data(bytes))
    }
}

@Test("isGzip recognises members and rejects everything else")
func magicDetection() throws {
    #expect(GzipMember.isGzip(try fixture("no-name")))
    #expect(!GzipMember.isGzip(Data([0x50, 0x4B, 0x03, 0x04])), "that is a ZIP")
    #expect(!GzipMember.isGzip(Data()))
    #expect(!GzipMember.isGzip(Data([0x1F])))
}

@Test("Arbitrary bytes never trap", arguments: [
    Data(), Data([0x1F]), Data([0x1F, 0x8B]), Data([0x1F, 0x8B, 0x08]),
    Data([0x1F, 0x8B, 0x09] + [UInt8](repeating: 0, count: 40)),
    Data(repeating: 0x1F, count: 200)
])
func neverTraps(payload: Data) {
    _ = try? GzipMember.decompress(payload)
    _ = GzipMember.isGzip(payload)
    #expect(Bool(true))
}

@Test("read(contentsOf:) accepts a plain file unchanged")
func plainFilePassesThrough() throws {
    let dir = try scratchDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("plain.jsonl")
    try #"{"a":1}"#.write(to: url, atomically: true, encoding: .utf8)
    #expect(String(decoding: try GzipMember.read(contentsOf: url), as: UTF8.self) == #"{"a":1}"#)
}
