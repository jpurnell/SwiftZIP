# SwiftZIP

Pure-Swift ZIP archive reader and writer, and a gzip reader. No vendored C code —
uses system zlib for compression level control and Apple's Compression framework as
the default.

## Features

- Read and write ZIP archives with stored and deflated entries
- Compression levels (fastest/fast/normal/best) via zlib, with Compression framework default
- Directory entries with Unix file permissions (644/755 defaults)
- Extended timestamps (UT extra field, 1-second precision) with DOS fallback
- ZIP64 extensions for archives exceeding 65,534 entries or 4GB sizes
- CRC-32 integrity verification on read
- Reads standalone gzip members (RFC 1952), a separate container over the same
  DEFLATE stream, with the trailing CRC-32 verified
- Unicode path support (accented, CJK, emoji characters)
- Swift 6 strict concurrency compliance (all types Sendable)

## Requirements

- Swift 6.0+
- macOS 14+ / iOS 17+

## Installation

Add SwiftZIP to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/jpurnell/SwiftZIP.git", from: "0.3.0"),
]
```

Then add it as a dependency to your target:

```swift
.target(name: "YourTarget", dependencies: ["SwiftZIP"]),
```

## Usage

### Writing a ZIP archive

```swift
import SwiftZIP

let entries = [
    ZIPEntry(path: "hello.txt", data: Data("Hello, World!".utf8)),
    ZIPEntry(path: "data.xml", data: Data("<root/>".utf8), method: .deflated, compressionLevel: .best),
    ZIPEntry(path: "script.sh", data: Data("#!/bin/sh".utf8), unixPermissions: 0o755),
    ZIPEntry.directory("src/"),
]

// Write to Data
let archiveData = try ZIPWriter.write(entries: entries)

// Write to file
try ZIPWriter.write(entries: entries, to: fileURL)
```

### Reading a ZIP archive

```swift
import SwiftZIP

// Read all entries
let entries = try ZIPReader.read(from: archiveData)
for entry in entries {
    print("\(entry.path): \(entry.data.count) bytes")
}

// Read a single entry by path
if let entry = try ZIPReader.readEntry(named: "hello.txt", from: archiveData) {
    let text = String(decoding: entry.data, as: UTF8.self)
}

// List entry paths without extracting
let paths = try ZIPReader.listEntries(in: archiveData)
```

### Reading a gzip file

```swift
import SwiftZIP

// Accepts .gz and plain files alike, so a caller that may receive either need not branch
let bytes = try GzipMember.read(contentsOf: url)

// Or decompress in memory, with the trailing CRC-32 checked
let out = try GzipMember.decompress(gzData)
```

## Limitations

- No encryption support
- No multi-disk archive support
- Archives and gzip members are read into memory; there is no streaming reader yet
- `GzipMember` reads the first member of a stream, not concatenated multi-member gzip

## License

MIT
