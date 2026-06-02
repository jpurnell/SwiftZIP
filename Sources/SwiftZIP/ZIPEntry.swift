import Foundation

/// A single entry in a ZIP archive, containing a file path and its data.
public struct ZIPEntry: Sendable, Equatable {
    /// The path of the entry within the archive.
    public let path: String
    /// The uncompressed data of the entry.
    public let data: Data
    /// The compression method used to store this entry.
    public let method: CompressionMethod
    /// The last modification date of the entry, or `nil` if unknown.
    public let modificationDate: Date?

    /// Creates a new ZIP entry.
    /// - Parameters:
    ///   - path: The path of the entry within the archive.
    ///   - data: The uncompressed data of the entry.
    ///   - method: The compression method to use. Defaults to `.stored`.
    ///   - modificationDate: The modification date. Defaults to `nil`,
    ///     which causes the writer to use the current date.
    public init(
        path: String,
        data: Data,
        method: CompressionMethod = .stored,
        modificationDate: Date? = nil
    ) {
        self.path = path
        self.data = data
        self.method = method
        self.modificationDate = modificationDate
    }
}
