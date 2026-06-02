import Foundation

extension Data {
    /// Appends a `UInt16` value in little-endian byte order.
    /// - Parameter value: The value to append.
    mutating func appendUInt16(_ value: UInt16) {
        let le = value.littleEndian
        append(UInt8(le & 0xFF))
        append(UInt8((le >> 8) & 0xFF))
    }

    /// Appends a `UInt32` value in little-endian byte order.
    /// - Parameter value: The value to append.
    mutating func appendUInt32(_ value: UInt32) {
        let le = value.littleEndian
        append(UInt8(le & 0xFF))
        append(UInt8((le >> 8) & 0xFF))
        append(UInt8((le >> 16) & 0xFF))
        append(UInt8((le >> 24) & 0xFF))
    }

    /// Reads a little-endian `UInt16` from the given byte offset.
    /// - Parameter offset: The byte offset to read from.
    /// - Returns: The decoded `UInt16` value.
    func readUInt16(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    /// Reads a little-endian `UInt32` from the given byte offset.
    /// - Parameter offset: The byte offset to read from.
    /// - Returns: The decoded `UInt32` value.
    func readUInt32(at offset: Int) -> UInt32 {
        UInt32(self[offset]) | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16) | (UInt32(self[offset + 3]) << 24)
    }

    /// Appends a `UInt64` value in little-endian byte order.
    /// - Parameter value: The value to append.
    mutating func appendUInt64(_ value: UInt64) {
        let le = value.littleEndian
        for shift in stride(from: 0, through: 56, by: 8) {
            append(UInt8((le >> shift) & 0xFF))
        }
    }

    /// Reads a little-endian `UInt64` from the given byte offset.
    /// - Parameter offset: The byte offset to read from.
    /// - Returns: The decoded `UInt64` value.
    func readUInt64(at offset: Int) -> UInt64 {
        var result: UInt64 = 0
        for i in 0..<8 {
            result |= UInt64(self[offset + i]) << (i * 8)
        }
        return result
    }
}
