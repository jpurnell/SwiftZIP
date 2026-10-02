import Foundation

/// Errors raised while reading or writing any container this package understands.
///
/// One vocabulary covers ZIP archives, gzip members, and zlib streams. Which container
/// failed is not carried in the error because the call site already names it: a
/// `.invalidSignature` out of ``GzipMember/decompress(_:limit:)`` means the data was not gzip,
/// and out of ``ZlibStream/inflate(_:limit:)`` that it was not zlib.
public enum ZIPError: Error, Equatable, Sendable {
    /// The data ends before a structure it declares, or is too short to hold one.
    case truncated
    /// The data does not carry the signature the reader expected.
    case invalidSignature
    /// A header is present but its contents are not readable — including a size or
    /// offset that does not fit in memory, or sizes the format makes impossible.
    case malformedHeader
    /// The end of central directory record was not found.
    case missingEndOfCentralDirectory
    /// An entry or member uses a compression method this package does not implement.
    case unsupportedCompressionMethod(UInt16)
    /// A CRC-32 check failed.
    ///
    /// `path` names the ZIP entry that failed, and is `nil` for gzip and zlib, which
    /// carry a checksum without a path to attach it to.
    case checksumMismatch(path: String?, expected: UInt32, actual: UInt32)
    /// The DEFLATE engine refused the data, or failed to start.
    case decompressionFailed(String)
    /// The input would cross one of the caller's ``ZIPLimits``.
    ///
    /// `value` is the size or count that crossed the limit and `maximum` the limit
    /// itself. For a size the input *declares*, `value` is that declaration, checked
    /// before anything is allocated. A zlib stream declares nothing, so its output stops
    /// one byte past the limit and `value` is `maximum + 1`.
    case limitExceeded(ZIPLimits.Limit, value: UInt64, maximum: UInt64)
}
