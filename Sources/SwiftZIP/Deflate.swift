import Foundation
#if canImport(Compression)
import Compression
#endif

/// Deflate compression and decompression for ZIP archives.
///
/// ZIP files use raw deflate (RFC 1951) without zlib headers. Apple's
/// `Compression` framework with `COMPRESSION_ZLIB` handles this correctly.
enum Deflate: Sendable {
    /// Decompresses raw-deflate data as used in ZIP archives.
    ///
    /// - Parameters:
    ///   - compressedData: The deflate-compressed bytes.
    ///   - uncompressedSize: The expected size of the decompressed output.
    /// - Returns: The decompressed data.
    /// - Throws: ``ZIPError/deflateError(_:)`` if decompression fails.
    static func decompress(_ compressedData: Data, uncompressedSize: Int) throws -> Data {
        guard uncompressedSize > 0 else { return Data() }

        #if canImport(Compression)
        return try decompressWithFramework(compressedData, uncompressedSize: uncompressedSize)
        #else
        throw ZIPError.deflateError("Deflate decompression not available on this platform")
        #endif
    }

    #if canImport(Compression)
    private static func decompressWithFramework(
        _ data: Data,
        uncompressedSize: Int
    ) throws -> Data {
        var destBuffer = [UInt8](repeating: 0, count: uncompressedSize)
        let decodedSize = data.withUnsafeBytes { srcPtr -> Int in
            guard let baseAddress = srcPtr.baseAddress else { return 0 }
            return compression_decode_buffer(
                &destBuffer, uncompressedSize,
                baseAddress.assumingMemoryBound(to: UInt8.self), data.count,
                nil,
                COMPRESSION_ZLIB
            )
        }
        guard decodedSize == uncompressedSize else {
            throw ZIPError.deflateError(
                "Decompression produced \(decodedSize) bytes, expected \(uncompressedSize)"
            )
        }
        return Data(destBuffer)
    }
    #endif

    /// Compresses data using Deflate for ZIP archives.
    ///
    /// - Parameter data: The uncompressed bytes to compress.
    /// - Returns: The deflate-compressed data.
    /// - Throws: ``ZIPError/deflateError(_:)`` if compression fails.
    static func compress(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return Data() }

        #if canImport(Compression)
        return try compressWithFramework(data)
        #else
        throw ZIPError.deflateError("Deflate compression not available on this platform")
        #endif
    }

    #if canImport(Compression)
    private static func compressWithFramework(_ data: Data) throws -> Data {
        // Deflate can occasionally expand small or incompressible inputs.
        // Allocate extra headroom to handle that case.
        let destCapacity = data.count + 512
        var destBuffer = [UInt8](repeating: 0, count: destCapacity)
        let compressedSize = data.withUnsafeBytes { srcPtr -> Int in
            guard let baseAddress = srcPtr.baseAddress else { return 0 }
            return compression_encode_buffer(
                &destBuffer, destCapacity,
                baseAddress.assumingMemoryBound(to: UInt8.self), data.count,
                nil,
                COMPRESSION_ZLIB
            )
        }
        guard compressedSize > 0 else {
            throw ZIPError.deflateError("Compression failed")
        }
        return Data(destBuffer[0..<compressedSize])
    }
    #endif
}
