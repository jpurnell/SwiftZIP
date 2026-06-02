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
    /// Unix file permissions (e.g., `0o644`), or `nil` if not set.
    public let unixPermissions: UInt16?

    /// Creates a new ZIP entry.
    /// - Parameters:
    ///   - path: The path of the entry within the archive.
    ///   - data: The uncompressed data of the entry.
    ///   - method: The compression method to use. Defaults to `.stored`.
    ///   - modificationDate: The modification date. Defaults to `nil`,
    ///     which causes the writer to use the current date.
    ///   - unixPermissions: Unix permission bits (e.g., `0o755`). Defaults
    ///     to `nil`, which causes the writer to use `0o644` for files
    ///     and `0o755` for directories.
    public init(
        path: String,
        data: Data,
        method: CompressionMethod = .stored,
        modificationDate: Date? = nil,
        unixPermissions: UInt16? = nil
    ) {
        self.path = path
        self.data = data
        self.method = method
        self.modificationDate = modificationDate
        self.unixPermissions = unixPermissions
    }

    /// Whether this entry represents a directory.
    public var isDirectory: Bool { path.hasSuffix("/") }

    /// Creates a directory entry.
    ///
    /// - Parameters:
    ///   - path: The directory path. A trailing `/` is appended if missing.
    ///   - modificationDate: The modification date. Defaults to `nil`.
    ///   - unixPermissions: Unix permission bits. Defaults to `nil` (`0o755`).
    /// - Returns: A stored, zero-length entry representing a directory.
    public static func directory(
        _ path: String,
        modificationDate: Date? = nil,
        unixPermissions: UInt16? = nil
    ) -> ZIPEntry {
        let dirPath = path.hasSuffix("/") ? path : path + "/"
        return ZIPEntry(
            path: dirPath,
            data: Data(),
            method: .stored,
            modificationDate: modificationDate,
            unixPermissions: unixPermissions
        )
    }
}
