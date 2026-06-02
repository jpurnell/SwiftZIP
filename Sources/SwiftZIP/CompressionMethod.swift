import Foundation

/// ZIP compression methods supported by this library.
public enum CompressionMethod: UInt16, Sendable {
    /// No compression (method 0).
    case stored = 0     // LIVE: public API for consumers
    /// Deflate compression (method 8).
    case deflated = 8   // LIVE: public API for consumers
}
