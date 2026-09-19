import Foundation

/// Reads a gzip member (RFC 1952).
///
/// Gzip is a single DEFLATE stream wrapped in a header and trailer — a different format
/// from the ZIP container this package is named for, but built from the same pieces:
/// this package's DEFLATE decoder decompresses the payload and its CRC-32 verifies it.
/// (Both are internal, so they are named here rather than linked.)
public enum GzipMember {

    /// Whether these bytes begin a gzip member.
    public static func isGzip(_ data: Data) -> Bool {
        guard data.count >= 2 else { return false }
        let first = data.index(data.startIndex, offsetBy: 0)
        let second = data.index(data.startIndex, offsetBy: 1)
        return data[first] == 0x1F && data[second] == 0x8B
    }

    /// Decompresses one gzip member, verifying its CRC-32.
    ///
    /// - Throws: ``ZIPError`` for any malformed shape, and
    ///   ``ZIPError/checksumMismatch(path:expected:actual:)`` — with a `nil` path, since a
    ///   bare member has none — when the bytes decompress but do
    ///   not match the recorded checksum. Corruption is **detected**, never returned: a
    ///   decompressor that cannot tell damaged input from good is worse than none,
    ///   because its output looks valid.
    public static func decompress(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count > 18 else { throw ZIPError.truncated }
        guard bytes[0] == 0x1F, bytes[1] == 0x8B else { throw ZIPError.invalidSignature }
        guard bytes[2] == 8 else { throw ZIPError.unsupportedCompressionMethod(UInt16(bytes[2])) }

        let flags = bytes[3]
        var offset = 10

        // FEXTRA: two-byte length, then that many bytes.
        if flags & 0x04 != 0 {
            guard offset + 1 < bytes.count else { throw ZIPError.malformedHeader }
            offset += 2 + (Int(bytes[offset]) | Int(bytes[offset + 1]) << 8)
        }
        // FNAME and FCOMMENT: NUL-terminated strings. `gzip -n` omits FNAME while a
        // plain `gzip` includes it, so a fixed 10-byte header reads some files and
        // silently misreads others.
        for mask in [UInt8(0x08), UInt8(0x10)] where flags & mask != 0 {
            while offset < bytes.count, bytes[offset] != 0 { offset += 1 }
            offset += 1
        }
        // FHCRC: two bytes.
        if flags & 0x02 != 0 { offset += 2 }
        guard offset >= 10, offset < bytes.count - 8 else { throw ZIPError.malformedHeader }

        let trailer = bytes.suffix(8)
        let expectedCRC = Self.littleEndian32(Array(trailer.prefix(4)))
        // ISIZE is the uncompressed size MODULO 2^32, so it is wrong above 4 GB. It
        // seeds the output buffer; the CRC decides correctness.
        let sizeHint = Int(Self.littleEndian32(Array(trailer.suffix(4))))

        let payload = Data(bytes[offset..<(bytes.count - 8)])
        let inflated = try Deflate.decompress(payload,
                                              uncompressedSize: max(sizeHint, 1))
        let actualCRC = CRC32.calculate(inflated)
        guard actualCRC == expectedCRC else {
            throw ZIPError.checksumMismatch(path: nil, expected: expectedCRC, actual: actualCRC)
        }
        return inflated
    }

    /// Reads a file, decompressing it only if it is a gzip member.
    ///
    /// Accepting both forms means a caller never has to ask which it has.
    public static func read(contentsOf url: URL) throws -> Data {
        let raw = try Data(contentsOf: url)
        return isGzip(raw) ? try decompress(raw) : raw
    }

    private static func littleEndian32(_ bytes: [UInt8]) -> UInt32 {
        guard bytes.count == 4 else { return 0 }
        return UInt32(bytes[0]) | UInt32(bytes[1]) << 8
             | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
    }
}
