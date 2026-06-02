# Changelog

All notable changes to SwiftZIP will be documented in this file.

## [0.2.0] - 2026-06-02

### Added
- Writer Deflate compression with automatic fallback to stored when compression doesn't reduce size
- MS-DOS timestamp encoding/decoding (`DOSTime`) for entry modification dates
- ZIP64 extensions for archives exceeding 65,534 entries or 4GB sizes
- `ZIPEntry.modificationDate` property for reading and writing timestamps
- ZIP64 EOCD record, locator, and extra field support in both reader and writer
- 21 new tests (109 total) covering deflate writing, timestamps, and ZIP64

### Changed
- `ZIPEntry` initializer now accepts optional `modificationDate` parameter
- Writer uses `UInt64` internally for size/offset tracking
- Reader parses ZIP64 EOCD locator and extra fields for large archives

## [0.1.0] - 2026-06-02

### Added
- Pure-Swift ZIP archive reader and writer with zero external dependencies
- CRC-32 calculation with lookup table verification
- Deflate decompression via Apple Compression framework
- Deflate compression support (internal, preparing for writer integration)
- ZIPEntry, ZIPWriter, ZIPReader, ZIPError public API
- Support for stored and deflated entries on read
- Unicode path support (accented, CJK, emoji)
- 88 tests covering round-trip, real-world OOXML, edge cases
- Swift 6 strict concurrency compliance (all types Sendable)
