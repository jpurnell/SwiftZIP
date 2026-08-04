# Design Proposal: SwiftZIP CLI Tool

**Status:** Proposal (not yet approved for implementation)
**Created:** 2026-06-02
**Scope:** Multi-phase roadmap — library enhancements + CLI executable

---

## 1. Objective

Turn SwiftZIP from a library-only package into a fully functional CLI tool (`swiftzip`)
that can serve as a pure-Swift replacement for `/usr/bin/zip` and `/usr/bin/unzip`
(Info-ZIP 3.0). The CLI is built on top of the library, which remains independently
usable.

**End state:** `swiftzip create`, `swiftzip extract`, `swiftzip list` handle the same
archives and options as Info-ZIP for the 95% use case, with full interoperability —
archives created by either tool are readable by the other.

---

## 2. Motivation

**Current situation:** SwiftZIP is a library that reads and writes ZIP archives with
stored/deflated entries, DOS timestamps, and ZIP64. There is no CLI interface, no
file-system integration, and several ZIP features needed for real-world interoperability
are missing (Unix permissions, extended timestamps, directory entries, comments).

**Why a CLI matters:**
- Scripting and automation without Python/shell dependency on Swift-native platforms
- Validates the library against real-world archives (dogfooding)
- Demonstrates completeness — if the CLI can replace `/usr/bin/zip`, the library is
  production-ready for embedding in apps
- Educational — a readable, well-tested Swift implementation of a ubiquitous format

**Why not just wrap Info-ZIP?**
- Info-ZIP is C from 2008 with global state, CVE history, and no concurrency safety
- Swift gives us memory safety, Sendable compliance, and SPM-native distribution
- A native implementation is testable at the byte level with Swift Testing

---

## 3. Current State (v0.3.0)

### What we have
| Capability | Status |
|---|---|
| Read stored + deflated entries | Done |
| Write stored + deflated entries | Done |
| Compression levels (1-9 via zlib) | Done (Phase 1A) |
| CRC-32 verification | Done |
| DOS timestamps (2-second, 1980-2107) | Done |
| Extended timestamps (UT, 1-second) | Done (Phase 1D) |
| ZIP64 (>65K entries, >4GB) | Done |
| Directory entries | Done (Phase 1B) |
| Unix file permissions | Done (Phase 1C) |
| Unicode paths (UTF-8) | Done |
| 125 tests, quality gate clean | Done |

### What we need (grouped by phase)

| Feature | Phase | Effort | Why |
|---|---|---|---|
| ~~Compression levels (1-9)~~ | ~~1~~ | ~~Small~~ | Done (v0.3.0) |
| ~~Directory entries~~ | ~~1~~ | ~~Small~~ | Done (v0.3.0) |
| ~~Unix file permissions~~ | ~~1~~ | ~~Small~~ | Done (v0.3.0) |
| ~~Extended timestamps (UT field)~~ | ~~1~~ | ~~Small~~ | Done (v0.3.0) |
| Streaming/incremental write API | 2 | Medium | Can't buffer multi-GB archives in memory |
| Data descriptors (bit 3) | 2 | Medium | Required for streaming writes |
| Archive/file comments | 2 | Small | `-c` / `-z` flags |
| Unix UID/GID extra fields | 2 | Small | Preserve ownership info |
| Symbolic link support | 2 | Medium | `-y` flag, special external attributes |
| CLI executable (ArgumentParser) | 3 | Medium | `swiftzip create/extract/list` |
| Recursive directory walking | 3 | Small | `-r` flag |
| Glob/pattern include/exclude | 3 | Small | `-x` / `-i` flags |
| Progress output | 3 | Small | Verbose/quiet modes |
| Cross-tool interop test suite | 3 | Medium | Validate against `/usr/bin/zip` |
| Password encryption (PKZIP) | 4 | Medium | `-e` flag, traditional encryption |
| AES-256 encryption | 4 | Large | WinZip AES extension |
| Archive repair (-F, -FF) | 4 | Large | Recovery from corruption |
| Self-extracting archives | 4 | Large | Low priority, niche use case |

---

## 4. Phase 1: Library Completeness (Foundation)

**Goal:** Make the library produce archives that are fully interoperable with
Info-ZIP for standard use cases (files with permissions and accurate timestamps).

### 4A. Compression Levels

**What:** Expose Compression framework's level parameter (1=fast through 9=best).
Currently we use the default level.

**API:**
```swift
public enum CompressionLevel: Int, Sendable {
    case fastest = 1
    case fast = 3
    case normal = 6
    case best = 9
}

// ZIPEntry gains a compressionLevel property
public struct ZIPEntry: Sendable, Equatable {
    public let path: String
    public let data: Data
    public let method: CompressionMethod
    public let modificationDate: Date?
    public let compressionLevel: CompressionLevel

    public init(
        path: String,
        data: Data,
        method: CompressionMethod = .stored,
        modificationDate: Date? = nil,
        compressionLevel: CompressionLevel = .normal
    )
}
```

**Implementation:** Pass `compressionLevel.rawValue` to `Deflate.compress()`.
Apple's Compression framework accepts `COMPRESSION_ZLIB` with a level hint via
the algorithm variant. If the framework doesn't expose levels directly, we
control the window/strategy parameters in our Deflate wrapper.

**Tests:**
- Level 1 compresses faster (or at least not slower) than level 9
- Level 9 produces smaller output than level 1 for compressible data
- All levels round-trip correctly
- Level is informational — reader doesn't need to know the level

**Effort:** Small (1-2 hours)

### 4B. Directory Entries

**What:** ZIP archives conventionally store directory entries as zero-length entries
with paths ending in `/`. Info-ZIP always writes these. We currently skip them.

**API:**
```swift
extension ZIPEntry {
    public var isDirectory: Bool { path.hasSuffix("/") }

    public static func directory(
        _ path: String,
        modificationDate: Date? = nil
    ) -> ZIPEntry
}
```

**Implementation:**
- Writer: when path ends in `/`, force method to `.stored`, data to empty,
  set external attributes bit 4 (MS-DOS directory flag)
- Reader: already handles these (zero-length stored entries), just surface
  the `isDirectory` computed property

**Tests:**
- Directory entry round-trips with trailing slash preserved
- Directory entry has zero data
- Mixed files and directories maintain order
- Reader recognizes existing directory entries from Info-ZIP archives

**Effort:** Small (1 hour)

### 4C. Unix File Permissions

**What:** ZIP external file attributes store Unix permission bits in the upper
16 bits (when version-made-by indicates Unix, platform code 3). Info-ZIP always
writes these.

**API:**
```swift
public struct ZIPEntry: Sendable, Equatable {
    // ... existing properties ...
    public let externalAttributes: UInt32

    // Convenience for Unix permissions
    public var unixPermissions: UInt16? {
        // Upper 16 bits when platform is Unix
    }
}
```

**Implementation:**
- Writer: set version-made-by upper byte to `3` (Unix), store permissions
  in upper 16 bits of external attributes. Default: `0o644` for files,
  `0o755` for directories.
- Reader: extract and expose via `externalAttributes` property.
  Compute `unixPermissions` from upper 16 bits.
- Central directory header field at offset 38 (external file attributes, 4 bytes)

**Tests:**
- Written permissions round-trip correctly
- Default permissions are sensible (644/755)
- Reader extracts permissions from Info-ZIP-created archives
- Non-Unix archives return nil for `unixPermissions`

**Effort:** Small (1-2 hours)

### 4D. Extended Timestamps (Universal Time Extra Field)

**What:** The UT extra field (tag `0x5455`) stores Unix timestamps with
1-second precision, supplementing the 2-second DOS timestamps. Info-ZIP
always writes these.

**Layout:**
```
Tag:    0x5455 (2 bytes)
Size:   varies (2 bytes)
Flags:  1 byte (bit 0 = mtime, bit 1 = atime, bit 2 = ctime)
mtime:  4 bytes (Unix epoch, little-endian) — if flag bit 0 set
atime:  4 bytes — if flag bit 1 set (central dir: only mtime)
ctime:  4 bytes — if flag bit 2 set (central dir: only mtime)
```

**API:** No new public properties needed — `modificationDate` already exists.
The writer emits the UT extra field alongside the DOS time fields. The reader
prefers UT timestamps over DOS timestamps when both are present.

**Implementation:**
- Writer: append UT extra field after any ZIP64 extra field. Include mtime only
  (flags = 0x01). Local header gets full mtime; central directory gets flags + mtime.
- Reader: scan extra fields for tag `0x5455`. If found, use its mtime instead of
  DOS time. Fall through to DOS time if not present.

**Tests:**
- UT timestamp round-trips with 1-second precision (vs 2-second for DOS)
- Reader prefers UT over DOS when both present
- Reader falls back to DOS when UT absent
- Odd-second timestamps survive round-trip (regression for DOS 2-second rounding)
- Archive is readable by `/usr/bin/unzip`

**Effort:** Small (2-3 hours)

---

## 5. Phase 2: Streaming & Metadata

**Goal:** Support archives larger than available memory and preserve full
file metadata.

### 5A. Streaming Write API

**What:** The current `write(entries:)` API buffers the entire archive in
memory. For multi-GB archives, this is impractical. A streaming API writes
entries incrementally to a file handle or output stream.

**API:**
```swift
public final class ZIPArchiveWriter: Sendable {
    public init(writingTo url: URL) throws
    public init(writingTo stream: OutputStream)

    public func addEntry(
        path: String,
        data: Data,
        method: CompressionMethod = .deflated,
        modificationDate: Date? = nil,
        compressionLevel: CompressionLevel = .normal
    ) throws

    public func addEntry(
        path: String,
        contentsOf url: URL,
        method: CompressionMethod = .deflated
    ) throws

    public func finalize() throws
}
```

**Implementation:**
- Write local file headers + data sequentially to the output
- Buffer central directory records in memory (small — just metadata)
- On `finalize()`, write central directory + EOCD/ZIP64
- Use data descriptors (bit 3) so we can stream without knowing
  compressed size upfront (see 5B)
- CRC-32 computed incrementally during write

**Key design decision:** `class` not `struct` because it wraps a file handle
with mutable state. Mark as `@unchecked Sendable` with internal locking,
or use an actor. Actor is cleaner but forces async API — discuss with user.

**Tests:**
- Streaming write produces identical archive to in-memory write
- Large file (>100MB) writes without memory spike
- `finalize()` called twice throws
- Adding entries after `finalize()` throws
- Round-trips through both streaming reader and in-memory reader

**Effort:** Medium (4-6 hours)

### 5B. Data Descriptors

**What:** When general purpose bit 3 is set, CRC-32 and sizes appear in a
data descriptor *after* the file data instead of in the local header. This
is required for streaming writes where the compressed size isn't known upfront.

**Layout (ZIP64 variant):**
```
Signature:         0x08074B50 (4 bytes, optional but conventional)
CRC-32:            4 bytes
Compressed size:   8 bytes (ZIP64) or 4 bytes
Uncompressed size: 8 bytes (ZIP64) or 4 bytes
```

**Implementation:**
- Writer: when streaming, set bit 3 in general purpose flags, write
  0 for CRC/sizes in local header, append data descriptor after file data
- Reader: detect bit 3, skip to data descriptor for CRC/sizes.
  Handle both with and without the optional signature prefix.

**Tests:**
- Archive with data descriptors round-trips correctly
- Reader handles archives with and without descriptor signature
- Interop: `/usr/bin/unzip` reads our data-descriptor archives

**Effort:** Medium (3-4 hours)

### 5C. Archive and File Comments

**What:** ZIP supports a per-archive comment (in the EOCD) and per-file
comments (in the central directory). Used by some tools for metadata.

**API:**
```swift
// Writing
public static func write(
    entries: [ZIPEntry],
    comment: String? = nil
) throws -> Data

// Reading
public struct ZIPArchiveInfo: Sendable {
    public let entries: [ZIPEntry]
    public let comment: String?
}
public static func readArchive(from data: Data) throws -> ZIPArchiveInfo

// Per-file
public struct ZIPEntry {
    // ... existing ...
    public let comment: String?
}
```

**Effort:** Small (1-2 hours)

### 5D. Unix UID/GID Extra Fields

**What:** Info-ZIP stores file ownership in extra field tag `0x7875`
(new Unix extra field) containing UID and GID as variable-length integers.

**API:**
```swift
public struct ZIPEntry {
    public let ownerID: UInt32?
    public let groupID: UInt32?
}
```

**Effort:** Small (1-2 hours)

### 5E. Symbolic Link Support

**What:** Info-ZIP stores symlinks by setting a flag in the external
attributes (Unix symlink bit `0o120000` in upper 16 bits) and storing
the link target path as the file data.

**API:**
```swift
extension ZIPEntry {
    public var isSymbolicLink: Bool
    public var symbolicLinkTarget: String?

    public static func symbolicLink(
        path: String,
        target: String,
        modificationDate: Date? = nil
    ) -> ZIPEntry
}
```

**Security consideration:** On extraction, symlink targets must be validated
to prevent path traversal attacks (e.g., `../../../etc/passwd`). The library
should expose the raw target but the CLI should validate before creating.

**Effort:** Medium (2-3 hours)

---

## 6. Phase 3: CLI Executable

**Goal:** Ship a usable `swiftzip` command-line tool.

### 6A. Package Structure

**New targets in Package.swift:**
```swift
.executableTarget(
    name: "swiftzip",
    dependencies: [
        "SwiftZIP",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
    ]
),
```

**Directory structure:**
```
Sources/
  SwiftZIP/           (existing library)
  swiftzip/           (CLI executable)
    SwiftZIPCommand.swift
    CreateCommand.swift
    ExtractCommand.swift
    ListCommand.swift
    TestCommand.swift
```

**New dependency:** `swift-argument-parser` (Apple's official CLI framework).
This is the only external dependency and it's build-time only — the library
target remains zero-dependency.

### 6B. CLI Commands

```
swiftzip create [-0..-9] [-r] [-y] [-c] [-z] [-x pattern] archive files...
swiftzip extract [-o] [-d dir] [-x pattern] archive [files...]
swiftzip list [-v] [-l] archive
swiftzip test archive
swiftzip info archive          (show archive metadata, comments, entry details)
```

**Command mapping to Info-ZIP:**
| swiftzip | /usr/bin/zip | /usr/bin/unzip |
|---|---|---|
| `create` | `zip` | — |
| `extract` | — | `unzip` |
| `list` | — | `unzip -l` |
| `test` | `zip -T` | `unzip -t` |

**Subcommand design (not flag-mode):** Unlike Info-ZIP's single-binary approach,
we use explicit subcommands. This is more discoverable and avoids the legacy
flag-overloading that makes `zip`/`unzip` hard to learn. Users who want
drop-in compatibility can alias:
```bash
alias zip='swiftzip create'
alias unzip='swiftzip extract'
```

### 6C. Recursive Directory Walking

**What:** `swiftzip create -r archive dir/` walks the directory tree and adds
all files, preserving relative paths.

**Implementation:**
- Use `FileManager.enumerator(at:)` with options for skipping hidden files
- Compute relative paths from the base directory
- Add directory entries for each subdirectory
- Preserve file permissions and timestamps from the filesystem
- Optionally follow or store symbolic links (`-y`)

**API (library level):**
```swift
extension ZIPWriter {
    public static func write(
        contentsOf directory: URL,
        to archiveURL: URL,
        method: CompressionMethod = .deflated,
        compressionLevel: CompressionLevel = .normal,
        includeHiddenFiles: Bool = false,
        followSymlinks: Bool = true
    ) throws
}
```

**Effort:** Small (2-3 hours)

### 6D. Glob/Pattern Matching

**What:** `-x pattern` excludes files matching a glob, `-i pattern` includes only
matching files. Standard shell glob syntax (`*`, `?`, `**`).

**Implementation:** Use `NSPredicate` with `LIKE` operator or a lightweight
glob matcher. Evaluate against each entry's relative path.

**Effort:** Small (2 hours)

### 6E. Progress and Output

**What:** Verbose mode shows each file as it's processed. Quiet mode suppresses
output. Default shows a summary.

```
$ swiftzip create -v archive.zip src/
  adding: src/                    (stored 0%)
  adding: src/main.swift          (deflated 68%)
  adding: src/utils.swift         (deflated 72%)
3 entries, 4.2 KB -> 1.8 KB (57% compression)
```

**Effort:** Small (1-2 hours)

### 6F. Cross-Tool Interoperability Test Suite

**What:** Automated tests that validate SwiftZIP archives against `/usr/bin/zip`
and `/usr/bin/unzip`, and vice versa. This is the strongest form of validation.

**Test categories:**
```swift
@Suite("Interoperability with Info-ZIP")
struct InteropTests {
    // SwiftZIP -> unzip
    @Test("Info-ZIP unzip reads SwiftZIP-created archive")
    func unzipReadsSwiftZIP() throws {
        // Create archive with SwiftZIP, extract with /usr/bin/unzip, compare
    }

    // zip -> SwiftZIP
    @Test("SwiftZIP reads Info-ZIP-created archive")
    func swiftZIPReadsInfoZIP() throws {
        // Create archive with /usr/bin/zip, read with SwiftZIP, compare
    }

    // Round-trip both directions
    @Test("Archives are byte-comparable for stored entries")
    func storedByteEquivalence() throws { ... }

    // Edge cases
    @Test("Unicode filenames survive cross-tool round-trip")
    @Test("Symlinks survive cross-tool round-trip")
    @Test("Empty directories survive cross-tool round-trip")
    @Test("Large files (>4GB) survive cross-tool round-trip")
    @Test("Permissions survive cross-tool round-trip")
}
```

**Implementation:** Tests shell out to `/usr/bin/zip` and `/usr/bin/unzip` via
`Process`, compare file contents and metadata. Guard with
`#if os(macOS)` or availability check since these binaries may not exist on Linux.

**Effort:** Medium (4-6 hours)

---

## 7. Phase 4: Advanced Features (Optional)

These features are lower priority. Include them only if there's a specific use case.

### 7A. Traditional PKZIP Encryption

**What:** The original ZIP encryption scheme. Weak by modern standards but
still widely used for basic password protection.

**Security note:** PKZIP encryption is cryptographically broken (known-plaintext
attacks). Document this clearly. For real security, recommend AES-256.

**Implementation:** Implements the PKZIP stream cipher using three 32-bit keys
derived from the password via CRC-32. Straightforward but needs careful
implementation to avoid timing side-channels.

**Effort:** Medium (4-6 hours)

### 7B. AES-256 Encryption (WinZip Extension)

**What:** The WinZip AES encryption extension (extra field tag `0x9901`).
Uses AES-256-CTR with HMAC-SHA1 authentication.

**Implementation:** Requires a cryptographic library. Options:
- Apple CryptoKit (macOS/iOS only)
- Swift Crypto (cross-platform, Apple-maintained)

This would be the first cross-platform dependency beyond Foundation.

**Effort:** Large (8-12 hours)

### 7C. Archive Repair

**What:** Attempt to recover entries from corrupted archives by scanning for
local file header signatures and reconstructing the central directory.

**Effort:** Large (8-12 hours)

### 7D. Self-Extracting Archives

**What:** Prepend a platform-specific executable stub to the archive.
Very niche use case.

**Effort:** Large, platform-specific. Low priority.

---

## 8. Constraints & Compliance

**Concurrency:** All library types remain Sendable. The streaming writer
(Phase 2) will be either an actor or `@unchecked Sendable` with a lock.

**Dependencies:**
- Library target: zero external dependencies (Foundation + Compression only)
- CLI target: `swift-argument-parser` only
- Encryption (Phase 4): `swift-crypto` if cross-platform AES is needed

**Safety:**
- No force unwraps, no `try!`, no force casts
- Path traversal validation on extraction (symlinks, `..` components)
- CRC-32 verification on all reads
- Bounds checking on all binary parsing

**Platform support:**
- macOS, Linux, Windows (library)
- macOS, Linux (CLI — Windows lacks `/usr/bin/zip` interop tests)

---

## 9. Estimated Timeline

| Phase | Scope | Effort | Can start after |
|---|---|---|---|
| Phase 1 | Library completeness | ~6-8 hours | Now |
| Phase 2 | Streaming & metadata | ~12-16 hours | Phase 1 |
| Phase 3 | CLI executable | ~12-16 hours | Phase 1 (partially Phase 2) |
| Phase 4 | Encryption & repair | ~20-30 hours | Phase 2 |

**Total to functional CLI (Phases 1-3):** ~30-40 hours of implementation time.

Phases are designed to be independently valuable:
- After Phase 1: library is interop-complete for standard archives
- After Phase 2: library handles large archives and preserves all metadata
- After Phase 3: usable CLI tool
- Phase 4: only if needed

---

## 10. Adversarial Review

**Strongest case for a different approach:**
Wrap libzip (C library) via SwiftPM C-target instead of reimplementing. libzip
handles every edge case, is actively maintained, and has its own test suite.
This would get to a working CLI in ~10 hours instead of ~40.

**Why we're not doing that:**
- libzip is LGPL (viral licensing concern for static linking in apps)
- C interop defeats the benefits listed in section 2 (safety, concurrency, testability)
- The point is a *Swift-native* implementation, not a wrapper

**Where this design is most likely wrong:**
The streaming writer API (Phase 2) may need to be async for server-side Swift use cases.
Designing it as synchronous first and adding async wrappers later is straightforward,
but if the primary consumer turns out to be server-side, we may want actor-based from
the start.

**What an experienced critic would say:**
"You're reimplementing a 40-year-old format from scratch when battle-tested C
implementations exist — you'll spend months on edge cases that libzip already handles."
We're proceeding because the library is already 80% there, the remaining work is
well-scoped, and the Swift ecosystem genuinely lacks a quality native ZIP library.

---

## 11. Open Questions

1. **Async streaming API?** Should `ZIPArchiveWriter` be an actor with async methods,
   or synchronous with a lock? Actor is cleaner for server-side Swift but forces
   `await` on every call.

2. **Compression level granularity:** Should we expose all 9 levels or just
   fastest/normal/best? Apple's Compression framework may not honor fine-grained levels.

3. **Linux CI:** Should we set up GitHub Actions for Linux builds? The library should
   work on Linux but we haven't tested it.

4. **Versioning:** Phase 1 = v0.3.0? Phase 3 (CLI) = v1.0.0?

5. **Executable naming:** `swiftzip` vs `szip` vs `sz`? Need to avoid conflicts
   with existing tools (7-Zip's `7z`, `szip` from HDF).

---

## 12. How to Use This Document

This is a reference roadmap, not a commitment. Each phase should go through the
full Design-First TDD workflow when you're ready to implement:

1. Pick a phase (or sub-feature within a phase)
2. Write a focused design proposal for that specific feature
3. RED: Write failing tests
4. GREEN: Implement
5. REFACTOR: Clean up
6. Quality gate, commit, push

You can implement phases out of order where dependencies allow. Phase 1 features
are all independent of each other. Phase 3 CLI can start as soon as Phase 1 is
done — it doesn't strictly require Phase 2 (streaming), though large-file support
would be limited.
