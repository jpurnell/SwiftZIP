import Testing
import Foundation
@testable import SwiftZIP

/// The zlib-backed Deflate paths, exercised directly so they run on every platform.
///
/// On Apple platforms `Deflate.decompress` uses the Compression framework, so
/// `decompressWithZlib` — the only inflate path on Linux — was never reached by the
/// macOS test run. `compressWithZlib` runs everywhere, but only when a level is given.
@Suite("zlib Deflate paths")
struct ZlibPathTests {

    private static func sample(_ count: Int) -> Data {
        // Compressible but not trivial: a repeating 251-byte cycle with a varying stride.
        Data((0..<count).map { UInt8(truncatingIfNeeded: ($0 % 251) &* 7 &+ ($0 / 1024)) })
    }

    @Test("zlib inflate round-trips what zlib deflate produced, at every size class",
          arguments: [1, 255, 4096, 65_537, 1_048_583])
    func roundTrip(count: Int) throws {
        let original = Self.sample(count)
        let compressed = try Deflate.compressWithZlib(original, level: 6)

        let restored = try Deflate.decompressWithZlib(compressed, uncompressedSize: count)

        #expect(restored == original)
    }

    @Test("zlib inflate round-trips every public compression level",
          arguments: [CompressionLevel.fastest, .fast, .normal, .best])
    func everyLevel(level: CompressionLevel) throws {
        let original = Self.sample(200_000)
        let compressed = try Deflate.compressWithZlib(original, level: Int32(level.rawValue))

        #expect(try Deflate.decompressWithZlib(compressed, uncompressedSize: original.count) == original)
    }

    @Test("zlib inflate agrees with the platform inflate on the same stream")
    func agreesWithPlatformPath() throws {
        let original = Self.sample(100_003)
        let compressed = try Deflate.compressWithZlib(original, level: 9)

        #expect(try Deflate.decompress(compressed, uncompressedSize: original.count)
                == Deflate.decompressWithZlib(compressed, uncompressedSize: original.count))
    }

    @Test("A declared size larger than the stream yields is refused by the zlib path")
    func declaredSizeTooLarge() throws {
        let original = Self.sample(4096)
        let compressed = try Deflate.compressWithZlib(original, level: 6)

        #expect(throws: ZIPError.decompressionFailed(
            "Decompression produced 4096 bytes, expected 4097")) {
            try Deflate.decompressWithZlib(compressed, uncompressedSize: 4097)
        }
    }

    @Test("A declared size smaller than the stream yields is refused by the zlib path")
    func declaredSizeTooSmall() throws {
        let original = Self.sample(4096)
        let compressed = try Deflate.compressWithZlib(original, level: 6)

        // -5 is Z_BUF_ERROR: Z_FINISH with too little room to finish the stream.
        #expect(throws: ZIPError.decompressionFailed("zlib inflate failed: -5")) {
            try Deflate.decompressWithZlib(compressed, uncompressedSize: 4095)
        }
    }
}
