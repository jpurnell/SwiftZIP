# SwiftZIP Master Plan

**Purpose:** Source of truth for project vision, architecture, and goals.

---

## Project Overview

### Mission
Provide a pure-Swift ZIP archive reader and writer with zero external dependencies, suitable for embedding in any Swift project that needs to create or parse ZIP files (including .xlsx, .docx, .jar, and other ZIP-based formats).

### Target Users
- **SwiftXLSX** (primary consumer) for reading and writing .xlsx archives
- **Swift library authors** who need ZIP support without pulling in heavyweight C dependencies
- **App developers** building document processing, backup, or file transfer features

### Key Differentiators
- **Zero external dependencies** -- Foundation + Compression framework only
- **Pure Swift** -- no C wrappers, no libz, no minizip
- **Read and write** -- both directions with a simple entry-based API
- **Deflate support** -- via Apple's Compression framework (`COMPRESSION_ZLIB`)
- **Sendable throughout** -- Swift 6 strict concurrency compliant
- **CRC-32 verification** -- integrity checking on read

---

## Architecture

### Technology Stack
- **Language:** Swift 6.0+
- **Frameworks:** Foundation, Compression (Apple system framework)
- **Build System:** Swift Package Manager
- **Testing:** Swift Testing framework + XCTest
- **Concurrency:** Swift 6 strict concurrency (all types Sendable)

### Module Structure

```
SwiftZIP/
├── Sources/SwiftZIP/
│   ├── ZIPEntry.swift           -- Archive entry (path + data + compression method)
│   ├── ZIPWriter.swift          -- Create ZIP archives
│   ├── ZIPReader.swift          -- Parse ZIP archives
│   ├── ZIPError.swift           -- Structured errors
│   ├── CompressionMethod.swift  -- .stored / .deflated
│   ├── Deflate.swift            -- Compress/decompress via Compression framework
│   ├── CRC32.swift              -- CRC-32 lookup table + calculation
│   └── DataHelpers.swift        -- Data extensions for reading/writing LE integers
├── Tests/SwiftZIPTests/
│   ├── CRC32Tests.swift
│   ├── ZIPWriterTests.swift
│   ├── DeflateTests.swift
│   ├── ZIPReaderTests.swift
│   ├── RoundTripTests.swift
│   └── RealWorldTests.swift
└── Package.swift
```

### Public API

```swift
// ZIPEntry -- one file in a ZIP archive
public struct ZIPEntry: Sendable, Equatable {
    public let path: String
    public let data: Data
    public let method: CompressionMethod
    public init(path: String, data: Data, method: CompressionMethod = .stored)
}

public enum CompressionMethod: UInt16, Sendable {
    case stored = 0
    case deflated = 8
}

// ZIPWriter -- create ZIP archives
public enum ZIPWriter {
    public static func write(entries: [ZIPEntry], to url: URL) throws
    public static func write(entries: [ZIPEntry]) throws -> Data
}

// ZIPReader -- read ZIP archives
public enum ZIPReader {
    public static func read(from url: URL) throws -> [ZIPEntry]
    public static func read(from data: Data) throws -> [ZIPEntry]
    public static func readEntry(named path: String, from data: Data) throws -> ZIPEntry?
    public static func listEntries(in data: Data) throws -> [String]
}

// ZIPError
public enum ZIPError: Error, Equatable, Sendable {
    case invalidSignature
    case missingEndOfCentralDirectory
    case unsupportedCompressionMethod(UInt16)
    case checksumMismatch(path: String, expected: UInt32, actual: UInt32)
    case deflateError(String)
    case truncatedArchive
}
```

### ZIP Format Implementation

**Write path:**
1. Local file header + raw data for each entry (stored, no compression in writer v1)
2. Central directory with file metadata
3. End of Central Directory Record (EOCD)

**Read path:**
1. Scan backwards from end of data to find EOCD signature (`0x06054B50`)
2. Parse EOCD to get central directory offset + entry count
3. Read central directory entries (paths, methods, sizes, CRC-32s, local header offsets)
4. For each entry: seek to local file header, parse, extract raw data
5. If method == `.deflated`: decompress via Compression framework
6. Verify CRC-32 of decompressed data

---

## Core Architectural Decisions

1. **Foundation + Compression only.** No external dependencies, ever. The Compression framework is an Apple system framework available on all target platforms.
2. **Entry-based API.** The unit of work is `[ZIPEntry]`, not streams or iterators. This is appropriate for the expected archive sizes (spreadsheets, documents) and keeps the API simple.
3. **Enum-based namespaces.** `ZIPWriter` and `ZIPReader` are caseless enums with static methods, not classes or structs. No state to manage.
4. **CRC-32 on read, not on write.** Writer stores CRC-32 for each entry; reader verifies it. Writer does not compress (entries stored as-is); reader decompresses Deflate.
5. **No ZIP64.** Maximum archive size is 4 GB, maximum entry count is 65,535. Sufficient for document formats. Documented limitation.
6. **No encryption.** Encrypted entries return `unsupportedCompressionMethod`. Documented limitation.
7. **Data descriptor support.** Reader handles bit 3 flag (sizes stored after entry data).

---

## Current Status

### What's Working
- [x] CRC-32 calculation with lookup table
- [x] Data helpers (read/write UInt16/UInt32 little-endian)
- [x] ZIPEntry + CompressionMethod + ZIPError types
- [x] ZIPWriter (stored entries, local headers + central directory + EOCD)
- [x] Deflate compress/decompress via Compression framework
- [x] ZIPReader (EOCD scan, central directory parse, entry extraction, Deflate decompression, CRC-32 verification)
- [x] Round-trip tests (write -> read -> verify)
- [x] Real-world tests (read actual .xlsx files produced by SwiftXLSX)
- [x] 88 tests passing, zero warnings

### Library Status: v0.1.0 -- Functional

The library handles the complete read/write cycle for ZIP archives with stored and Deflated entries. It is the ZIP backend for SwiftXLSX.

### Current Priorities
1. Development-guidelines setup (this step)
2. Writer compression support (Deflate on write, not just read)
3. Streaming reader for large archives (future)

---

## Quality Standards

### Code Quality
- All code follows `coding_rules.md`
- No force unwraps (`!`), no `try!`, no force casts (`as!`)
- All types must be Sendable
- Zero warnings in build output
- `swift build && swift test` must pass before every commit

### Documentation Quality
- DocC comments for all public APIs
- Usage examples in documentation

---

## Roadmap

### Phase 1: Core Types + Writer ✅ COMPLETE
- [x] CRC32, DataHelpers, ZIPEntry, CompressionMethod, ZIPError
- [x] ZIPWriter (stored entries)

### Phase 2: Deflate + Reader ✅ COMPLETE
- [x] Deflate compress/decompress via Compression framework
- [x] ZIPReader (EOCD scan, central directory, entry extraction, CRC-32 verify)

### Phase 3: Tests + Integration ✅ COMPLETE
- [x] CRC32Tests, ZIPWriterTests, DeflateTests, ZIPReaderTests
- [x] RoundTripTests, RealWorldTests
- [x] SwiftXLSX migrated to depend on SwiftZIP
- [x] All 88 SwiftZIP tests + all 1490 SwiftXLSX tests passing

### Phase 4: Polish (Current)
- [ ] Development-guidelines integration
- [ ] Writer Deflate support (compress on write for smaller archives)
- [ ] Progress callback for large archives
- [ ] README.md with usage examples

### Future Considerations
- Streaming reader (process entries without loading entire archive into memory)
- Linux support (pure-Swift Deflate behind `#if !canImport(Compression)`)
- ZIP64 for archives > 4 GB
- Password-protected archives

---

**Last Updated:** 2026-06-02 (initial master plan; 88 tests; v0.1.0)
