import Foundation

/// Controls the effort spent on Deflate compression.
///
/// Higher levels produce smaller output at the cost of slower compression.
/// The reader does not need to know the level — all levels decompress identically.
public enum CompressionLevel: Int, Sendable, Equatable {
    /// Fastest compression (zlib level 1).
    case fastest = 1  // LIVE: public API for consumers
    /// Fast compression (zlib level 3).
    case fast = 3     // LIVE: public API for consumers
    /// Balanced compression (zlib level 5, matches Apple Compression framework).
    case normal = 5   // LIVE: public API for consumers
    /// Best compression ratio (zlib level 9).
    case best = 9     // LIVE: public API for consumers
}
