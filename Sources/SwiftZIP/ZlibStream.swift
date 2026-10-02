import Foundation
import CZlib

/// Reads a zlib-wrapped DEFLATE stream (RFC 1950).
///
/// The third container this package reads over the same DEFLATE engine. A ZIP entry is raw
/// deflate with no wrapper; a gzip member wraps it in an RFC 1952 header and trailer; a
/// zlib stream wraps it in a two-byte header and an Adler-32 trailer.
///
/// It exists because this package's internal DEFLATE path cannot serve this case: a ZIP entry's central directory
/// declares its uncompressed size, so that path takes the size as an argument. A bare zlib
/// stream declares nothing, and the case that motivated this — an iTunes `.itl` database —
/// inflates 81 MB to 514 MB. The output buffer therefore grows as needed rather than being
/// allocated from a number the caller does not have.
public enum ZlibStream: Sendable {


    /// Whether the data begins with a valid zlib header.
    ///
    /// A zlib header is two bytes: a compression-method/window byte whose low nibble is 8
    /// for DEFLATE, and a flags byte chosen so the pair is a multiple of 31. Both are
    /// checked, because the multiple-of-31 rule is what distinguishes a real header from
    /// two arbitrary bytes that happen to start with `0x78`.
    ///
    /// - Parameter data: Bytes to inspect.
    /// - Returns: `true` when the first two bytes are a zlib header.
    public static func isZlib(_ data: Data) -> Bool {
        guard data.count >= 2 else { return false }
        let cmf = Int(data[data.startIndex])
        let flg = Int(data[data.index(after: data.startIndex)])
        guard cmf & 0x0F == 8 else { return false }
        return (cmf << 8 | flg) % 31 == 0
    }

    /// Inflates a zlib-wrapped stream whose output size is unknown.
    ///
    /// Nothing in a zlib stream declares its output size, so the ceiling is enforced on
    /// the bytes actually produced: inflation stops one byte past `limit`, and a
    /// decompression bomb costs at most that much memory.
    ///
    /// - Parameters:
    ///   - data: The complete compressed stream.
    ///   - limit: The largest inflated size accepted, in bytes. Defaults to
    ///     ``ZIPLimits/defaultMaxEntryUncompressedSize`` (1 GiB).
    /// - Returns: The inflated bytes.
    /// - Throws: ``ZIPError/limitExceeded(_:value:maximum:)`` when the output would pass
    ///   `limit`, and ``ZIPError`` when the header is wrong, the stream is truncated, or
    ///   zlib rejects the data — which includes a failed Adler-32, so silent corruption
    ///   is reported rather than returned.
    public static func inflate(
        _ data: Data,
        limit: UInt64 = ZIPLimits.defaultMaxEntryUncompressedSize
    ) throws -> Data {
        guard data.count >= 2 else { throw ZIPError.truncated }
        guard isZlib(data) else { throw ZIPError.invalidSignature }

        var stream = z_stream()
        // 15 rather than -15: positive window bits mean "expect a zlib wrapper", which is
        // exactly the difference between this and `Deflate`'s raw path.
        let started = inflateInit2_(&stream, 15, ZLIB_VERSION,
                                    Int32(MemoryLayout<z_stream>.size))
        guard started == Z_OK else { throw ZIPError.decompressionFailed("zlib inflateInit failed: \(started)") }
        defer { inflateEnd(&stream) }

        var output = Data()
        var chunk = [UInt8](repeating: 0, count: chunkSize)
        var source = [UInt8](data)
        var status: Int32 = Z_OK
        // zlib counts input in 32-bit `uInt`; a larger buffer is refused, not truncated
        // into a trap by `uInt(_:)`.
        guard let availableIn = uInt(exactly: source.count) else {
            throw ZIPError.decompressionFailed("input of \(source.count) bytes exceeds one zlib call")
        }

        try source.withUnsafeMutableBufferPointer { input in
            stream.next_in = input.baseAddress
            stream.avail_in = availableIn

            repeat {
                let window = outputWindow(produced: output.count, limit: limit)
                let produced: Int = chunk.withUnsafeMutableBufferPointer { out -> Int in
                    stream.next_out = out.baseAddress
                    stream.avail_out = uInt(window)
                    status = CZlib.inflate(&stream, Z_NO_FLUSH)
                    return window - Int(stream.avail_out)
                }

                guard status == Z_OK || status == Z_STREAM_END || status == Z_BUF_ERROR else {
                    throw ZIPError.decompressionFailed("zlib inflate failed: \(status)")
                }
                if produced > 0 { output.append(contentsOf: chunk[0..<produced]) }
                guard UInt64(output.count) <= limit else {
                    throw ZIPError.limitExceeded(.entryUncompressedSize,
                                                 value: UInt64(output.count), maximum: limit)
                }

                // Z_BUF_ERROR with nothing produced and nothing left to read means zlib
                // wants more input that will never arrive: the stream is truncated.
                if status == Z_BUF_ERROR, produced == 0, stream.avail_in == 0 {
                    throw ZIPError.truncated
                }
            } while status != Z_STREAM_END
        }

        guard status == Z_STREAM_END else { throw ZIPError.truncated }
        return output
    }

    /// How many bytes the next pass may produce.
    ///
    /// A full chunk while the limit is far off; near it, exactly one byte more than the
    /// limit allows, so crossing it is detected without inflating any further.
    ///
    /// - Parameters:
    ///   - produced: Bytes inflated so far, never more than `limit`.
    ///   - limit: The caller's ceiling.
    /// - Returns: A window size in `1...chunkSize`.
    private static func outputWindow(produced: Int, limit: UInt64) -> Int {
        let room = limit - UInt64(produced)
        guard let roomInt = Int(exactly: room) else { return chunkSize }
        return min(roomInt, chunkSize - 1) + 1
    }

    /// Bytes inflated per pass.
    ///
    /// 256 KiB trades a modest allocation against the number of round trips on a large
    /// stream: the motivating `.itl` needs roughly two thousand passes at this size rather
    /// than half a million at 1 KiB.
    private static let chunkSize = 256 * 1024
}
