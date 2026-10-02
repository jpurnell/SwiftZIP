# Changelog

All notable changes to SwiftZIP will be documented in this file.

## [Unreleased]

## [0.8.0] - 2026-10-02

Reading is now safe on untrusted input: no archive, gzip member, or zlib stream can trap
the process, and none can make the reader allocate beyond the caller's limits.

### Added
- `ZIPLimits`, a `Sendable` set of ceilings: `maxEntryUncompressedSize` (default 1 GiB),
  `maxTotalUncompressedSize` (default 4 GiB), and `maxEntryCount` (default 65,536). The
  sizes are `UInt64` so the defaults are expressible where `Int` is 32 bits (watchOS)
- `limits:` parameters, defaulting to `ZIPLimits.default`, on `ZIPReader.read(from:)` (both
  overloads), `readEntry(named:from:)` and `listEntries(in:)`; `limit:` parameters on
  `GzipMember.decompress(_:)`, `GzipMember.read(contentsOf:)` and `ZlibStream.inflate(_:)`.
  Existing calls compile unchanged
- `ZIPError.limitExceeded(_:value:maximum:)`, naming the limit crossed and both values
- watchOS 10 and visionOS 1 in `platforms:`, verified with `xcodebuild` for generic
  watchOS (arm64 and arm64_32) and visionOS

### Changed
- **Breaking for exhaustive `switch`es over `ZIPError`**: the new `limitExceeded` case
- Declared sizes are checked **before** allocation. A deflated entry declaring more than
  DEFLATE's maximum expansion (1032:1) of its compressed size, or a stored entry whose
  two sizes disagree, throws `.malformedHeader`. A size over the limits throws
  `.limitExceeded`. Previously a ~100-byte archive could make the reader allocate 4 GiB
- `GzipMember` checks its ISIZE trailer against the limit and against the payload before
  using it as a buffer size. Previously a 20-byte member could request 4 GiB
- `ZlibStream.inflate` stops one byte past its limit instead of inflating without bound
- `GzipMember` is now declared `Sendable`
- A test fixture's temp-directory containment check compares path components instead of a
  string prefix, ahead of the quality gate reporting a bare prefix as an error.

### Fixed
- ZIP64 sizes, offsets, and counts at or above 2^63 (2^31 on 32-bit watchOS), and 32-bit
  fields on 32-bit platforms, trapped in `Int(_:)`. They now throw `.malformedHeader`;
  offset-plus-length sums are overflow-checked and throw `.truncated`
- A ZIP64 locator pointing past `Int.max` trapped on `offset + 56`; it is now ignored as
  any other unusable locator is
- A central directory entry count was reserved before it was checked, so a ZIP64 count
  could request terabytes. The count is now limited, and must fit in the bytes present
- Reading a `Data` slice (non-zero `startIndex`) misread every offset; slices are now
  rebased before parsing
- README claimed Swift 6.0+; the manifest has always declared swift-tools-version 6.2


## [0.7.0] - 2026-09-19

### Changed
- **Breaking.** One error vocabulary for every container. `GzipMember.Failure` and
  `ZlibStream.Failure` are gone; `ZIPReader`, `ZIPWriter`, `GzipMember` and `ZlibStream`
  all throw `ZIPError`. Three enums had grown to fifteen cases that did not agree — two
  nested types both named `Failure`, `checksumMismatch` carrying a path in one and not
  the other, and "input ended early" spelled three ways. Seven cases now cover all of it.
  Which container failed is told by the call you made, not by the error
- `ZIPError.truncatedArchive` is now `.truncated`; `.deflateError(_:)` is now
  `.decompressionFailed(_:)`
- `ZIPError.checksumMismatch` takes `path: String?`. A gzip member has a checksum but no
  path to attach it to, and optional is more honest than an empty string
- Unified deliberately before 1.0, which freezes the vocabulary. Doing it after would
  cost a major version

### Added
- Apache 2.0 license and NOTICE, making the package usable by the public it is published
  to (shipped in 3780269, unreleased until now)

### Fixed
- README advertised a ZIP64 threshold of 65,534 entries; the format's limit is 65,535

## [0.6.0] - 2026-08-25

### Added
- `ZlibStream` reads zlib-wrapped DEFLATE (RFC 1950) — the third container over the same
  engine, alongside raw deflate for ZIP entries and RFC 1952 for gzip
- Inflates streams whose output size is **unknown**, growing the buffer as needed.
  `Deflate` cannot serve this case: a ZIP entry's central directory declares its
  uncompressed size, so that path takes the size as an argument, while a bare zlib stream
  declares nothing
- `ZlibStream.isZlib(_:)` validates both header bytes, including the multiple-of-31 rule
  that distinguishes a real header from two bytes that merely start with `0x78`
- Corruption is detected via zlib's Adler-32 and reported, never returned
- `GzipMember` reads standalone gzip members (RFC 1952) -- a different container from
  ZIP, built from the pieces already here: the existing `Deflate` decoder unwrapped by
  a gzip header and trailer, with `CRC32` verifying the result
- Variable-length header parsing (FEXTRA, FNAME, FCOMMENT, FHCRC). A fixed 10-byte
  header decodes a `gzip -n` file correctly and silently corrupts a plain `gzip` one,
  so both variants are covered by committed fixtures
- Corruption is detected via the trailing CRC-32 and reported, never returned
- `GzipMember.read(contentsOf:)` accepts compressed and plain files alike, so callers
  that may receive either need not branch
- `GzipMember.isGzip(_:)` for magic-number detection
- DocC catalogue (`SwiftZIP.docc`) -- the package had none

### Fixed
- Documentation described an API that does not exist: an instance `ZIPReader(data:)`
  with `.entries` and `.extract(_:)`. The real type is a caseless enum of static
  methods returning `[ZIPEntry]`. Caught by the gate's doc-code checker, which
  compiles documentation fences
- Doc examples on `ZIPReader` and `ZIPWriter` did not compile: they referenced
  undefined `fileURL`, `archiveData`, and `data`, and `ZIPReader`'s fence declared
  `let entries` twice in one scope
- The DocC article did not run. It opened with `let archiveData = Data()` and read it
  — an empty `Data` is a *truncated* archive, not an empty one, so the article trapped
  on `ZIPError.truncatedArchive`. Its gzip example also read a `/tmp` path that need
  not exist. Both now build the input they consume

### Changed
- Test fixtures for gzip are committed rather than generated by spawning `/usr/bin/gzip`
  during the run. The spawn was an unbounded child process in the suite, and made
  results depend on whichever gzip the host shipped
- `.docc` catalogue and test fixtures are declared as target resources, so SwiftPM no
  longer reports unhandled files
- `.quality-gate.yml` sets `enabledCheckers: [all]`. Five checkers, `doc-run` and
  `doc-comment-code` among them, sit outside the default selection, which is why the
  broken examples above went unnoticed until this release

### Notes
- 144 tests, quality gate 0 errors / 0 warnings across 45 of 45 checkers
- **Version jumps 0.3.0 -> 0.6.0.** A `0.5.0` tag existed once and was lost when the
  guidelines-layout refactor rewrote history; the commit it named is gone. Reissuing
  0.5.0 on different content, or releasing a 0.4.0 that sorts below it, would both keep
  that ambiguity alive. 0.6.0 is unambiguously past the gap. `0.4.0` and `0.5.0` are
  retired and will not be published
- Verified against a real 313 MB `.gz`: 620,455,926 bytes, 127,029 records
- `GzipMember` reads the first member of a stream; concatenated multi-member gzip is
  not yet handled, which covers every file in use

## [0.3.0] - 2026-06-02

### Added
- Compression levels (`CompressionLevel`: fastest/fast/normal/best) via zlib
- Apple Compression framework remains the default when no level is specified
- zlib backend for explicit level control (system library, zero vendored code)
- zlib-based decompression fallback for non-Apple platforms
- Directory entry support with `ZIPEntry.directory()` factory and `isDirectory` property
- Unix file permissions in external attributes (`unixPermissions` property)
- Extended timestamps via Universal Time extra field (tag 0x5455, 1-second precision)
- Reader prefers UT timestamps over DOS timestamps when available
- Writer sets Unix platform (3) in version-made-by field
- Default permissions: `0o644` for files, `0o755` for directories
- 16 new tests (125 total) covering compression levels, directories, permissions, and extended timestamps

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

[Unreleased]: https://github.com/jpurnell/SwiftZIP/compare/0.8.0...HEAD
[0.8.0]: https://github.com/jpurnell/SwiftZIP/compare/0.7.0...0.8.0
[0.7.0]: https://github.com/jpurnell/SwiftZIP/compare/0.6.0...0.7.0
[0.6.0]: https://github.com/jpurnell/SwiftZIP/compare/0.3.0...0.6.0
[0.3.0]: https://github.com/jpurnell/SwiftZIP/releases/tag/0.3.0
[0.2.0]: https://github.com/jpurnell/SwiftZIP/commit/ccf81a3
[0.1.0]: https://github.com/jpurnell/SwiftZIP/commit/1c6209e
