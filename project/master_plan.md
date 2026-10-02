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
│   ├── ZIPLimits.swift          -- Ceilings on untrusted input (0.8.0)
│   ├── CompressionMethod.swift  -- .stored / .deflated
│   ├── GzipMember.swift         -- Read RFC 1952 gzip members (header + DEFLATE + CRC-32)
│   ├── ZlibStream.swift         -- Read RFC 1950 zlib streams of unknown output size
│   ├── Deflate.swift            -- Compress/decompress via Compression framework and zlib
│   ├── CompressionLevel.swift   -- Deflate level, carried per entry
│   ├── DOSTime.swift            -- MS-DOS date/time encoding
│   ├── CRC32.swift              -- CRC-32 lookup table + calculation
│   ├── DataHelpers.swift        -- Data extensions for reading/writing LE integers
│   └── SwiftZIP.docc/           -- DocC catalogue (fences are compiled by doc-code)
├── Sources/CZlib/               -- systemLibrary shim over libz
├── Tests/SwiftZIPTests/
│   ├── CRC32Tests.swift
│   ├── ZIPWriterTests.swift
│   ├── DeflateTests.swift
│   ├── ZIPReaderTests.swift
│   ├── RoundTripTests.swift
│   ├── GzipMemberTests.swift
│   ├── RealWorldTests.swift
│   ├── ZlibStreamTests.swift
│   ├── ZIP64Tests.swift
│   ├── UntrustedInputTests.swift -- hand-built hostile archives, gzip and zlib (0.8.0)
│   └── Fixtures/gzip/, Fixtures/zlib/           -- gzip members produced by the system gzip, committed
└── Package.swift
```

### Public API

```swift
// ZIPEntry -- one file in a ZIP archive
public struct ZIPEntry: Sendable, Equatable {
    public let path: String
    public let data: Data
    public let method: CompressionMethod
    public let modificationDate: Date?
    public let unixPermissions: UInt16?
    public let compressionLevel: CompressionLevel?
    public init(path: String, data: Data, method: CompressionMethod = .stored,
                modificationDate: Date? = nil, unixPermissions: UInt16? = nil,
                compressionLevel: CompressionLevel? = nil)
    public static func directory(_ path: String, modificationDate: Date? = nil,
                                 unixPermissions: UInt16? = nil) -> ZIPEntry
}

public enum CompressionMethod: UInt16, Sendable { case stored = 0, deflated = 8 }
public enum CompressionLevel: Int, Sendable, Equatable { case fastest = 1, fast = 3, normal = 5, best = 9 }

// ZIPWriter / ZIPReader -- create and parse ZIP archives
public enum ZIPWriter: Sendable {
    public static func write(entries: [ZIPEntry], to url: URL) throws
    public static func write(entries: [ZIPEntry]) throws -> Data
}

public enum ZIPReader: Sendable {
    public static func read(from url: URL, limits: ZIPLimits = .default) throws -> [ZIPEntry]
    public static func read(from data: Data, limits: ZIPLimits = .default) throws -> [ZIPEntry]
    public static func readEntry(named path: String, from data: Data,
                                 limits: ZIPLimits = .default) throws -> ZIPEntry?
    public static func listEntries(in data: Data, limits: ZIPLimits = .default) throws -> [String]
}

// ZIPLimits -- ceilings on untrusted input (0.8.0)
public struct ZIPLimits: Sendable, Equatable {
    public enum Limit: String, Sendable, Equatable {
        case entryUncompressedSize, totalUncompressedSize, entryCount
    }
    public static let defaultMaxEntryUncompressedSize: UInt64   // 1 GiB
    public static let defaultMaxTotalUncompressedSize: UInt64   // 4 GiB
    public static let defaultMaxEntryCount: Int                 // 65,536
    public var maxEntryUncompressedSize: UInt64
    public var maxTotalUncompressedSize: UInt64
    public var maxEntryCount: Int
    public init(maxEntryUncompressedSize: UInt64 = ..., maxTotalUncompressedSize: UInt64 = ...,
                maxEntryCount: Int = ...)
    public static let `default`: ZIPLimits
}

// GzipMember / ZlibStream -- the other two containers over the same DEFLATE engine
public enum GzipMember: Sendable {
    public static func isGzip(_ data: Data) -> Bool
    public static func decompress(_ data: Data, limit: UInt64 = ZIPLimits.defaultMaxEntryUncompressedSize) throws -> Data
    public static func read(contentsOf url: URL, limit: UInt64 = ZIPLimits.defaultMaxEntryUncompressedSize) throws -> Data
}

public enum ZlibStream: Sendable {
    public static func isZlib(_ data: Data) -> Bool
    public static func inflate(_ data: Data, limit: UInt64 = ZIPLimits.defaultMaxEntryUncompressedSize) throws -> Data
}

// ZIPError -- one vocabulary for all three containers (0.7.0)
public enum ZIPError: Error, Equatable, Sendable {
    case truncated
    case invalidSignature
    case malformedHeader
    case missingEndOfCentralDirectory
    case unsupportedCompressionMethod(UInt16)
    case checksumMismatch(path: String?, expected: UInt32, actual: UInt32)
    case decompressionFailed(String)
    case limitExceeded(ZIPLimits.Limit, value: UInt64, maximum: UInt64)   // 0.8.0
}
```

### ZIP Format Implementation

**Write path:**
1. Local file header + entry data, stored or Deflated per the entry's method
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
4. **CRC-32 on read, not on write.** Writer stores CRC-32 for each entry; reader verifies it. ~~Writer does not compress (entries stored as-is)~~ — **superseded.** The writer has compressed since Phase 4, with the level carried per entry via `CompressionLevel`. The original decision is kept here because it explains why `CompressionMethod` defaults to `.stored`.
5. ~~**No ZIP64.** Maximum archive size is 4 GB, maximum entry count is 65,535. Sufficient for document formats. Documented limitation.~~ — **superseded.** "Sufficient for document formats" was wrong within three months: SwiftXLSX needed archives past the 65,535-entry limit, and ZIP64 shipped. Recorded rather than deleted, because the reasoning was sound and the premise was not.
6. **No encryption.** Encrypted entries return `unsupportedCompressionMethod`. Documented limitation. Still true.
7. **Data descriptor support.** Reader handles bit 3 flag (sizes stored after entry data).
8. **One error vocabulary.** Every container throws `ZIPError`; which one failed is told by the call site, not carried in the error. See `plans/proposals/0002-UnifiedErrors.md`. Settled in 0.7.0 because 1.0 freezes it.
9. **Input is untrusted (0.8.0).** Every size, count, and offset read from the input is converted with `Int(exactly:)` and range ends are overflow-checked, so no input can trap. Declared sizes are checked before allocation twice: against what the format allows (stored sizes must agree; DEFLATE cannot expand past 1032:1) and against caller-overridable `ZIPLimits`. Until 0.8.0 the reader trusted declared sizes, which was tolerable while every consumer read archives it had written itself, and stopped being tolerable when polar-ble-sdk proposed reading firmware fetched over the network.

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
- [x] Writer Deflate support -- entries compress on write, level carried per entry
- [x] ZIP64 (archives > 4 GB and > 65,535 entries)
- [x] gzip reader (`GzipMember`) -- variable-length RFC 1952 header, CRC-32 verified
- [x] DocC catalogue. This line previously claimed the fences were compiled by the
      gate's doc-code checker. They were not: `doc-code`, `doc-run`, and
      `doc-comment-code` sit outside the default checker selection, so nothing
      compiled them and five examples were broken. Fixed and the full set enabled
      in 0.6.0
- [x] Untrusted-input hardening (0.8.0) -- checked integer conversion, plausibility of
      declared sizes, `ZIPLimits` ceilings on ZIP, gzip and zlib reads
- [x] watchOS 10 and visionOS 1 declared in `platforms:` (0.8.0), verified by
      `xcodebuild` for generic watchOS (arm64 and arm64_32) and visionOS
- [x] 163 tests passing

### Library Status: v0.7.0 shipped (one error vocabulary)

The library handles the complete read/write cycle for ZIP archives with stored and
Deflated entries, including ZIP64. It is the ZIP backend for SwiftXLSX, and now also
reads standalone gzip members for concordance.

Reading gzip stretched the package past its name. The two formats are different
containers over the same DEFLATE stream, so `GzipMember` reuses `Deflate` and `CRC32`
outright; nothing was duplicated to add it. The name is now slightly narrower than
the contents, which is worth noting but not worth a rename.

0.7.0 finished what that growth started. Each container had arrived with its own error
enum, and by three containers they no longer agreed — fifteen cases, two types both
named `Failure`, and "input ended early" spelled three ways. They are one seven-case
`ZIPError` now. It is a breaking change, taken deliberately at 0.x rather than
inherited into 1.0, which freezes the vocabulary.

### Current Priorities
1. ~~Development-guidelines setup~~ -- done, vendored
2. ~~Writer compression support (Deflate on write, not just read)~~ -- shipped
3. ~~One error vocabulary across the three containers~~ -- shipped in 0.7.0
4. Streaming reader for large archives -- still the main gap, and now the largest
   single item standing between here and 1.0. `GzipMember` decodes a 313 MB member to
   620 MB in memory, which works but does not scale.

### The road to 1.0

**1.0 ships when the roadmap below is complete, not when the API feels settled.**

The public surface is already stable enough to freeze — nothing outstanding requires a
breaking change, which is why 0.7.0 spent its breaking change now rather than saving it.
What 1.0 additionally promises is that the documented limitations are gone, not merely
documented. Those are the Future Considerations below, and each is additive:

| For 1.0 | Additive? | Why it is not done |
|---|---|---|
| Streaming reader | yes — new entry points beside `read(from:)` | the main gap; whole archive is held in memory |
| Progress callback | yes — needs the same incremental path | belongs with streaming, not before it |
| Linux support | yes — pure-Swift Deflate behind `#if !canImport(Compression)` | untested; `platforms:` declares Apple platforms only (macOS, iOS, watchOS, visionOS since 0.8.0) |
| Multi-member gzip | behaviour change, so before 1.0 | `GzipMember` reads the first member only |
| Password-protected archives | yes | no consumer has asked |

If any of these turns out to need a breaking change after all, it takes the version with
it — the promise is semver, not a date.

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

### Phase 4: Polish ✅ COMPLETE
- [x] ~~Development-guidelines integration~~
- [x] ~~Writer Deflate support (compress on write for smaller archives)~~
- [x] ~~README.md with usage examples~~
- [ ] Progress callback for large archives -- not built; belongs with the streaming
      reader below, since both need the same incremental read path

### Phase 5: gzip ✅ COMPLETE
- [x] `GzipMember` -- RFC 1952 header/trailer around the existing DEFLATE decoder
- [x] Corruption detected via the trailing CRC-32, never returned to the caller
- [x] Fixtures from the system gzip, committed rather than generated in-process

### Phase 6: One Error Vocabulary ✅ COMPLETE (0.7.0)
- [x] `GzipMember.Failure` and `ZlibStream.Failure` folded into `ZIPError`
- [x] Fifteen cases across three types reduced to seven in one
- [x] Loose `#expect(throws: (any Error).self)` in `ZlibStreamTests` tightened to named cases
- [x] `plans/proposals/0002-UnifiedErrors.md` records the mapping and the reasoning

### Phase 6½: Untrusted Input (0.8.0, unreleased)
- [x] Every archive-supplied integer converted with `Int(exactly:)`; range ends overflow-checked
- [x] Declared sizes checked for plausibility and against `ZIPLimits` before allocation
- [x] `GzipMember` ISIZE capped and checked against the payload; `ZlibStream` output ceiling
- [x] A `Data` slice reads correctly (previously misread every offset by its start index)
- [x] watchOS 10 / visionOS 1 added to `platforms:` after building for both

Not on the original roadmap at all: it was prompted by a consumer (polar-ble-sdk)
replacing an unmaintained ZIP library over a path-traversal advisory, which made the
question "what does a hostile archive cost us?" concrete.

### Phase 7: 1.0 — the items below, complete

These were "Future Considerations" when the plan was written. They are now the
definition of 1.0 rather than a wishlist beside it; see **The road to 1.0** above.

- Streaming reader (process entries without loading entire archive into memory)
- Linux support (pure-Swift Deflate behind `#if !canImport(Compression)`)
- ~~ZIP64 for archives > 4 GB~~ -- **shipped.** Listed here as a future consideration
  when the plan was written; it moved to Current Status once SwiftXLSX needed archives
  above the 65,535-entry limit.
- Multi-member gzip streams (concatenated members) -- `GzipMember` reads the first
  member only, which covers every file we have. Unlike the rest of this list this one
  changes existing behaviour, so it lands before 1.0 or not at all
- Password-protected archives

---

**Last Updated:** 2026-10-02 -- untrusted-input hardening on `fix/untrusted-sizes`, ahead
of 0.8.0 (not yet tagged). Added `ZIPLimits` and `ZIPError.limitExceeded` to the Public API
block, Core Architectural Decision 9, Phase 6½, the new source and test files, the
watchOS/visionOS platforms, and the test count (163). The 144 recorded earlier had
already drifted before this change.

*Previous entry, 2026-09-19:* reconciled for the 0.7.0 release. Folded the three error
enums into one and recorded the decision as Core Architectural Decision 8. Corrected two
decisions this plan had kept asserting after the code stopped agreeing: #4 still said the
writer does not compress, and #5 still said "No ZIP64" with the note that 4 GB was
"sufficient for document formats" — it was not sufficient within three months. Both are
struck through with the reasoning kept, rather than deleted. Replaced the Public API block
wholesale: it had never been updated past 0.1 and omitted `CompressionLevel`, `ZlibStream`,
`GzipMember`, and four of `ZIPEntry`'s six initialiser parameters. Added `ZlibStream.swift`
and two test files to the module structure. Recast the Future Considerations as Phase 7,
which is now the definition of 1.0.

*Previous entry, 2026-08-25:* reconciled for the 0.6.0 release. Recorded `ZlibStream`
alongside `GzipMember`, corrected the test count to 144, and set Library Status to v0.6.0
(it still read "v0.3.0 shipped; gzip is unreleased on main"). Corrected this plan's own
claim that the DocC fences were compiled by the gate: `doc-code`, `doc-run`, and
`doc-comment-code` are outside the default checker selection, so nothing compiled them and
five examples were broken until 0.6.0 enabled the full set.

*Previous entry, 2026-08-22:* reconciled against shipped code. The plan had drifted:
it recorded 88 tests (now 136), listed ZIP64 as a future consideration when it had
already shipped, described Deflate as reaching zlib through the Compression framework
alone when a `CZlib` systemLibrary target was added in June, and carried a Phase 4
whose items were all complete. Added `GzipMember`, the DocC catalogue, and the
`CZlib`/Fixtures entries to the module structure.
