# SwiftZIP

Pure-Swift ZIP archive reader and writer with zero external dependencies.

## Features

- Read and write ZIP archives with stored and deflated entries
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
    ZIPEntry(path: "data.xml", data: Data("<root/>".utf8)),
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

- No ZIP64 support (max 4 GB archive, 65,535 entries)
- No encryption support
- Writer currently supports stored entries only (deflated write planned for v0.2.0)

## License

MIT
