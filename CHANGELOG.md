# Changelog

All notable changes to SwiftZIP will be documented in this file.

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
