# ``SwiftZIP``

Read and write ZIP archives, and read gzip members, in pure Swift.

## Overview

SwiftZIP implements the two container formats built on DEFLATE, with no dependency
beyond zlib for the compression itself:

- **ZIP** — the archive format, via ``ZIPReader`` and ``ZIPWriter``. Both understand
  ZIP64, so archives above 4 GiB or 65,535 entries round-trip correctly.
- **gzip** — the single-stream format, via ``GzipMember``. A gzip file is not a ZIP
  file; it is one DEFLATE stream between an RFC 1952 header and trailer.

Every read path is total: malformed, truncated, or hostile input returns a
``ZIPError`` or a ``GzipMember/Failure``, and never traps.

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

### Reading a gzip file

``GzipMember/read(contentsOf:)`` accepts both compressed and plain files, so a
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

### Reading gzip

- ``GzipMember``

### Compression settings

- ``CompressionLevel``
- ``CompressionMethod``

### Errors

- ``ZIPError``
