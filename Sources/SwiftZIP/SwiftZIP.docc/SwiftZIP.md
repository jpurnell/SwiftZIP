# ``SwiftZIP``

Read and write ZIP archives, and read gzip members, in pure Swift.

## Overview

SwiftZIP implements the two container formats built on DEFLATE, with no dependency
beyond zlib for the compression itself:

- **ZIP** — the archive format, via ``ZIPReader`` and ``ZIPWriter``. Both understand
  ZIP64, so archives above 4 GiB or 65,535 entries round-trip correctly.
- **gzip** — the single-stream format, via ``GzipMember``. A gzip file is not a ZIP
  file; it is one DEFLATE stream between an RFC 1952 header and trailer.

Every read path is total: malformed, truncated, or hostile input throws a
``ZIPError`` and never traps. One vocabulary covers all three containers — which one
failed is told by the call you made, not by the error.

### Reading an archive

```swift
import Foundation
import SwiftZIP

// A real archive to read back: an empty `Data()` is a truncated archive, not an
// empty one, and reading it throws.
let archiveData = try ZIPWriter.write(entries: [
    ZIPEntry(path: "notes.txt", data: Data("hello".utf8))
])
for entry in try ZIPReader.read(from: archiveData) where !entry.isDirectory {
    print(entry.path, entry.data.count)
}
```

Entries decompress as they are read, so ``ZIPEntry/data`` is the plain bytes.
Writing is the mirror image:

```swift
import Foundation
import SwiftZIP

let entries = [ZIPEntry(path: "notes.txt", data: Data("hello".utf8))]
let archive = try ZIPWriter.write(entries: entries)
```

### Reading untrusted input

An archive declares its own sizes, and a hostile one lies about them. Every size,
count, and offset it declares is converted without trapping, and every declared size
is checked before anything is allocated: against what the format makes possible, and
against ``ZIPLimits`` — by default 1 GiB per entry, 4 GiB in total, and 65,536 entries.
A caller that knows its payloads are small should say so:

```swift
import Foundation
import SwiftZIP

let downloaded = try ZIPWriter.write(entries: [
    ZIPEntry(path: "firmware.bin", data: Data(repeating: 0xA5, count: 256))
])
let limits = ZIPLimits(maxEntryUncompressedSize: 16 << 20,
                       maxTotalUncompressedSize: 64 << 20,
                       maxEntryCount: 64)
do {
    let entries = try ZIPReader.read(from: downloaded, limits: limits)
    print(entries.map(\.path))
} catch ZIPError.limitExceeded(let limit, let value, let maximum) {
    print("refused: \(limit.rawValue) \(value) > \(maximum)")
}
```

``GzipMember`` and ``ZlibStream`` take the same ceiling as a `limit:` argument.

### Reading a gzip file

``GzipMember/read(contentsOf:limit:)`` accepts both compressed and plain files, so a
caller that may receive either does not have to branch:

```swift
import Foundation
import SwiftZIP

let url = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("index.jsonl")
try Data("{\"ok\":true}\n".utf8).write(to: url)

let bytes = try GzipMember.read(contentsOf: url)   // .gz or not
```

Correctness is checked, not assumed: the trailing CRC-32 is verified against the
decompressed bytes, so silent corruption is reported rather than returned.

## Topics

### Reading and writing archives

- ``ZIPReader``
- ``ZIPWriter``
- ``ZIPEntry``

### Reading gzip and zlib

- ``GzipMember``
- ``ZlibStream``

### Untrusted input

- ``ZIPLimits``

### Compression settings

- ``CompressionLevel``
- ``CompressionMethod``

### Errors

- ``ZIPError``
