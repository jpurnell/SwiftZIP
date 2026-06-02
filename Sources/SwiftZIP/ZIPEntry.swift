import Foundation

/// A single entry in a ZIP archive, containing a file path and its data.
public struct ZIPEntry: Sendable, Equatable {
    /// The path of the entry within the archive.
    public let path: String
    /// The uncompressed data of the entry.
    public let data: Data
    /// The compression method used to store this entry.
    public let method: CompressionMethod

    /// Creates a new ZIP entry.
    /// - Parameters:
    ///   - path: The path of the entry within the archive.
    ///   - data: The uncompressed data of the entry.
    ///   - method: The compression method to use. Defaults to `.stored`.
    public init(path: String, data: Data, method: CompressionMethod = .stored) {
        self.path = path
        self.data = data
        self.method = method
    }
}
