import Foundation

/// Errors that can occur during ZIP read or write operations.
public enum ZIPError: Error, Equatable, Sendable {
    /// The data does not contain a valid ZIP signature.
    case invalidSignature
    /// The end of central directory record was not found.
    case missingEndOfCentralDirectory
    /// An entry uses an unsupported compression method.
    case unsupportedCompressionMethod(UInt16)
    /// CRC-32 mismatch after decompression.
    case checksumMismatch(path: String, expected: UInt32, actual: UInt32)
    /// Deflated data could not be decompressed.
    case deflateError(String)
    /// The archive is truncated or corrupted.
    case truncatedArchive
}
