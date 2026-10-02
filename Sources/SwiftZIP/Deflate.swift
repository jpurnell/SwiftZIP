import Foundation
#if canImport(Compression)
import Compression
#endif
import CZlib

/// Deflate compression and decompression for ZIP archives.
///
/// ZIP files use raw deflate (RFC 1951) without zlib headers. When no
/// compression level is specified, the Apple Compression framework is used
/// (fixed at level 5). When a specific level is requested, zlib is called
/// directly to honor the level parameter.
enum Deflate: Sendable {
    /// DEFLATE's maximum expansion: no stream inflates to more than 1032 times its size.
    ///
    /// The longest match is 258 bytes, and the cheapest way to encode one costs a little
    /// over two bits, so a byte of input can never yield more than 1032 bytes of output.
    /// zlib's own documentation states this bound ("Technical Details": "the limit is
    /// 1032:1"). It needs no tuning: it is a property of the format, not a policy.
    static let maxExpansionRatio: UInt64 = 1032

    /// Whether `compressedSize` bytes of DEFLATE could possibly inflate to
    /// `uncompressedSize` bytes.
    ///
    /// A declaration that fails this is a lie, and is refused before it is allocated.
    static func canExpand(_ compressedSize: UInt64, to uncompressedSize: UInt64) -> Bool {
        let (bound, overflow) = compressedSize.multipliedReportingOverflow(by: maxExpansionRatio)
        // An overflowing bound exceeds every UInt64, so any declared size is reachable.
        return overflow || uncompressedSize <= bound
    }

    /// Decompresses raw-deflate data as used in ZIP archives.
    ///
    /// - Parameters:
    ///   - compressedData: The deflate-compressed bytes.
    ///   - uncompressedSize: The expected size of the decompressed output.
    /// - Returns: The decompressed data.
    /// - Throws: ``ZIPError/decompressionFailed(_:)`` if decompression fails.
    static func decompress(_ compressedData: Data, uncompressedSize: Int) throws -> Data {
        guard uncompressedSize > 0 else { return Data() }

        #if canImport(Compression)
        return try decompressWithFramework(compressedData, uncompressedSize: uncompressedSize)
        #else
        return try decompressWithZlib(compressedData, uncompressedSize: uncompressedSize)
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
            throw ZIPError.decompressionFailed(
                "Decompression produced \(decodedSize) bytes, expected \(uncompressedSize)"
            )
        }
        return Data(destBuffer)
    }
    #endif

    /// Compresses data using Deflate for ZIP archives.
    ///
    /// - Parameters:
    ///   - data: The uncompressed bytes to compress.
    ///   - level: The compression level, or `nil` to use the framework default.
    /// - Returns: The deflate-compressed data.
    /// - Throws: ``ZIPError/decompressionFailed(_:)`` if compression fails.
    static func compress(_ data: Data, level: CompressionLevel? = nil) throws -> Data {
        guard !data.isEmpty else { return Data() }

        if let level {
            return try compressWithZlib(data, level: Int32(level.rawValue))
        }

        #if canImport(Compression)
        return try compressWithFramework(data)
        #else
        return try compressWithZlib(data, level: Z_DEFAULT_COMPRESSION)
        #endif
    }

    #if canImport(Compression)
    private static func compressWithFramework(_ data: Data) throws -> Data {
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
            throw ZIPError.decompressionFailed("Compression failed")
        }
        return Data(destBuffer[0..<compressedSize])
    }
    #endif

    private static func compressWithZlib(_ data: Data, level: Int32) throws -> Data {
        var stream = z_stream()
        let initResult = deflateInit2_(
            &stream,
            level,
            Z_DEFLATED,
            -15, // raw deflate (no zlib header)
            8,   // default memory level
            Z_DEFAULT_STRATEGY,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initResult == Z_OK else {
            throw ZIPError.decompressionFailed("zlib deflateInit2 failed: \(initResult)")
        }

        let destCapacity = Int(deflateBound(&stream, UInt(data.count)))
        var destBuffer = [UInt8](repeating: 0, count: destCapacity)
        let srcBytes = [UInt8](data)

        var srcCopy = srcBytes
        srcCopy.withUnsafeMutableBufferPointer { srcBuf in
            stream.next_in = srcBuf.baseAddress
            stream.avail_in = uInt(srcBuf.count)
        }

        let compressedSize: Int
        do {
            destBuffer.withUnsafeMutableBufferPointer { dstBuf in
                stream.next_out = dstBuf.baseAddress
                stream.avail_out = uInt(dstBuf.count)
            }

            let result = CZlib.deflate(&stream, Z_FINISH)
            compressedSize = Int(stream.total_out)
            deflateEnd(&stream)

            guard result == Z_STREAM_END else {
                // compressedSize will be checked below but we need to handle the error path
                throw ZIPError.decompressionFailed("zlib deflate failed: \(result)")
            }
        } catch {
            throw error
        }

        return Data(destBuffer[0..<compressedSize])
    }

    // LIVE: used on non-Apple platforms where Compression framework is unavailable
    private static func decompressWithZlib(
        _ data: Data, uncompressedSize: Int
    ) throws -> Data {
        var stream = z_stream()
        let initResult = inflateInit2_(
            &stream,
            -15, // raw deflate
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initResult == Z_OK else {
            throw ZIPError.decompressionFailed("zlib inflateInit2 failed: \(initResult)")
        }

        // zlib counts bytes in 32-bit `uInt`; sizes beyond that are refused rather than
        // trapped on by `uInt(_:)`.
        guard let availableIn = uInt(exactly: data.count),
              let availableOut = uInt(exactly: uncompressedSize) else {
            inflateEnd(&stream)
            throw ZIPError.decompressionFailed("entry exceeds what one zlib call can address")
        }

        var destBuffer = [UInt8](repeating: 0, count: uncompressedSize)
        var srcCopy = [UInt8](data)

        srcCopy.withUnsafeMutableBufferPointer { srcBuf in
            stream.next_in = srcBuf.baseAddress
            stream.avail_in = availableIn
        }

        destBuffer.withUnsafeMutableBufferPointer { dstBuf in
            stream.next_out = dstBuf.baseAddress
            stream.avail_out = availableOut
        }

        let result = CZlib.inflate(&stream, Z_FINISH)
        let decodedSize = Int(stream.total_out)
        inflateEnd(&stream)

        guard result == Z_STREAM_END else {
            throw ZIPError.decompressionFailed("zlib inflate failed: \(result)")
        }

        guard decodedSize == uncompressedSize else {
            throw ZIPError.decompressionFailed(
                "Decompression produced \(decodedSize) bytes, expected \(uncompressedSize)"
            )
        }
        return Data(destBuffer[0..<decodedSize])
    }
}
