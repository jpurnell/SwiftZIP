# SwiftZIP

Pure-Swift ZIP archive reader and writer with zero external dependencies.

## Features

- Read and write ZIP archives with stored and deflated entries
- Writer Deflate compression with automatic fallback when compression doesn't help
- MS-DOS modification timestamps (2-second resolution, 1980-2107 range)
- ZIP64 extensions for archives exceeding 65,534 entries or 4GB sizes
- CRC-32 integrity verification on read
- Unicode path support (accented, CJK, emoji characters)
- Swift 6 strict concurrency compliance (all types Sendable)
- Foundation + Apple Compression framework only

## Requirements

- Swift 6.0+
- macOS 14+ / iOS 17+

## Installation

Add SwiftZIP to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/jpurnell/SwiftZIP.git", from: "0.1.0"),
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
    ZIPEntry(path: "data.xml", data: Data("<root/>".utf8), method: .deflated),
    ZIPEntry(path: "dated.txt", data: Data("timestamped".utf8), modificationDate: Date()),
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

## Limitations

- No encryption support
- No multi-disk archive support

## License

MIT
