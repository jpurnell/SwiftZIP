import Foundation

/// CRC-32 checksum calculator using the standard polynomial (0xEDB88320).
enum CRC32 {
    /// Precomputed lookup table for CRC-32 calculation.
    static let table: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var crc = UInt32(i)
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ 0xEDB88320
                } else {
                    crc >>= 1
                }
            }
            return crc
        }
    }()

    /// Calculates the CRC-32 checksum of the given data.
    /// - Parameter data: The data to compute the checksum for.
    /// - Returns: The CRC-32 checksum as a `UInt32`.
    static func calculate(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = (crc >> 8) ^ table[index]
        }
        return crc ^ 0xFFFFFFFF
    }
}
