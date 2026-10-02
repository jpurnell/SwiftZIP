import Foundation

/// Ceilings on what reading an untrusted archive, gzip member, or zlib stream may cost.
///
/// An archive declares its own sizes, and a hostile one lies: a hundred-byte ZIP can
/// claim a 4 GiB entry, and a 20-byte gzip member can claim a 4 GiB output. Every read
/// path checks the declared sizes against these limits **before allocating**, and the
/// streaming paths also stop when the bytes actually produced cross the ceiling, so a
/// decompression bomb costs at most the limit plus one byte.
///
/// Limits are a second line of defence. Independently of them, a declared size that
/// the format makes impossible — a stored entry whose two sizes disagree, or a deflated
/// entry claiming more than DEFLATE's maximum expansion of 1032:1 — is rejected as
/// ``ZIPError/malformedHeader``, and no size or offset read from the input is ever
/// converted to `Int` without a check. Lifting every ceiling therefore re-admits large
/// honest archives, not traps.
///
/// ## Choosing the defaults
///
/// ``default`` is sized so that no realistic document, spreadsheet, or firmware
/// package reaches it, while a bomb is stopped well before it exhausts a phone's memory:
///
/// - **1 GiB per entry.** An `.xlsx` worksheet, a firmware image, or a JSON payload is
///   megabytes; a gibibyte is two orders of magnitude of headroom, and still a sum a
///   watch or phone can refuse rather than attempt.
/// - **4 GiB in total.** Four maximum-size entries, and the point at which an archive
///   needs ZIP64 to exist at all. A reader that legitimately needs more is reading
///   trusted data and should say so with its own limits.
/// - **65,536 entries.** One past the largest count a non-ZIP64 archive can declare
///   (65,535). Every entry costs a record in memory before any data is read, so the
///   count is limited before the central directory is walked.
///
/// ```swift
/// import Foundation
/// import SwiftZIP
///
/// let archive = try ZIPWriter.write(entries: [
///     ZIPEntry(path: "firmware.bin", data: Data(repeating: 0, count: 64))
/// ])
/// // A caller that knows its payloads are small says so.
/// let tight = ZIPLimits(maxEntryUncompressedSize: 16 * 1024 * 1024,
///                       maxTotalUncompressedSize: 64 * 1024 * 1024,
///                       maxEntryCount: 32)
/// let entries = try ZIPReader.read(from: archive, limits: tight)
/// print(entries.count)
/// ```
public struct ZIPLimits: Sendable, Equatable {

    /// Names the ceiling an input crossed, as carried by ``ZIPError/limitExceeded(_:value:maximum:)``.
    public enum Limit: String, Sendable, Equatable {
        /// ``ZIPLimits/maxEntryUncompressedSize``: one ZIP entry, gzip member, or zlib stream.
        case entryUncompressedSize
        /// ``ZIPLimits/maxTotalUncompressedSize``: the sum over every entry of one archive.
        case totalUncompressedSize
        /// ``ZIPLimits/maxEntryCount``: the number of entries an archive declares.
        case entryCount
    }

    /// The default ceiling on one entry's uncompressed size: 1 GiB.
    public static let defaultMaxEntryUncompressedSize: UInt64 = 1 << 30
    /// The default ceiling on an archive's total uncompressed size: 4 GiB.
    public static let defaultMaxTotalUncompressedSize: UInt64 = 1 << 32
    /// The default ceiling on an archive's entry count: 65,536.
    public static let defaultMaxEntryCount = 65_536

    /// The largest uncompressed size accepted for a single ZIP entry, gzip member, or
    /// zlib stream, in bytes.
    ///
    /// `UInt64` rather than `Int` because the defaults must be expressible where `Int` is
    /// 32 bits wide (watchOS on arm64_32), and because declared sizes are 64-bit.
    public var maxEntryUncompressedSize: UInt64
    /// The largest sum of declared uncompressed sizes accepted across one archive, in bytes.
    public var maxTotalUncompressedSize: UInt64
    /// The largest number of entries an archive may declare.
    public var maxEntryCount: Int

    /// Creates a set of limits; any limit not given keeps its default.
    ///
    /// - Parameters:
    ///   - maxEntryUncompressedSize: Ceiling on one entry's uncompressed bytes.
    ///   - maxTotalUncompressedSize: Ceiling on the archive's total uncompressed bytes.
    ///   - maxEntryCount: Ceiling on the number of entries.
    public init(
        maxEntryUncompressedSize: UInt64 = ZIPLimits.defaultMaxEntryUncompressedSize,
        maxTotalUncompressedSize: UInt64 = ZIPLimits.defaultMaxTotalUncompressedSize,
        maxEntryCount: Int = ZIPLimits.defaultMaxEntryCount
    ) {
        self.maxEntryUncompressedSize = maxEntryUncompressedSize
        self.maxTotalUncompressedSize = maxTotalUncompressedSize
        self.maxEntryCount = maxEntryCount
    }

    /// 1 GiB per entry, 4 GiB in total, 65,536 entries. See the type's discussion for
    /// why these values.
    public static let `default` = ZIPLimits()
}
