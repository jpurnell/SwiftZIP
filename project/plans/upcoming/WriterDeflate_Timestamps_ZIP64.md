# Design Proposal: Writer Deflate, Modification Timestamps, and ZIP64 Extensions

**Date:** 2026-06-02
**Status:** Proposed
**Master Plan Reference:** Phase 4 — Polish

---

## 1. Objective

Add three capabilities to SwiftZIP that close the practical gap between this library and production ZIP tools:

1. **Writer Deflate support** — compress entries on write, producing archives 2–3x smaller for XML-heavy document formats
2. **Modification timestamps** — populate the mod time/date fields in local and central directory headers instead of zeroing them
3. **ZIP64 extensions** — support archives >4 GB, entries >4 GB, and >65,535 entries

---

## 2. Motivation

**Writer Deflate:**
- Current situation: `ZIPWriter` only supports stored entries (method 0). It rejects `.deflated` entries with an error.
- Workaround: Consumers accept the size penalty or post-process with an external tool.
- Drawback: .xlsx files produced by SwiftXLSX via SwiftZIP are ~2–3x larger than those from Excel or other tools. The `Deflate.compress` function already exists and works — it just isn't wired into the writer.

**Timestamps:**
- Current situation: All local and central directory headers write `0x0000` for mod time and mod date.
- Workaround: None — the zero values silently persist.
- Drawback: `unzip -l` shows `1980-00-00 00:00` for every entry. ZIP validators flag it. Tools that use timestamps for freshness checks (like incremental backup) see all entries as equally stale.

**ZIP64:**
- Current situation: Entry count is `UInt16` (max 65,535), sizes and offsets are `UInt32` (max ~4 GB).
- Workaround: None — archives silently produce corrupt data if limits are exceeded.
- Drawback: While unlikely for document formats today, silent data corruption is worse than a clear error. ZIP64 is the standard mechanism for exceeding these limits.

---

## 3. Proposed Architecture

**Modified Files:**
- `Sources/SwiftZIP/ZIPWriter.swift` — Deflate on write, timestamps, ZIP64 EOCD
- `Sources/SwiftZIP/ZIPReader.swift` — Parse ZIP64 EOCD locator and ZIP64 extra fields
- `Sources/SwiftZIP/ZIPEntry.swift` — Add optional `modificationDate` property
- `Sources/SwiftZIP/DataHelpers.swift` — Add `appendUInt64` / `readUInt64` for ZIP64 fields
- `Sources/SwiftZIP/Deflate.swift` — No changes (compress already works, remove `// LIVE:` annotation)

**New Files:**
- `Sources/SwiftZIP/DOSTime.swift` — MS-DOS time/date encoding and decoding

**No new modules.** All changes stay within the existing `SwiftZIP` target.

---

## 4. API Surface

### Feature A: Writer Deflate

No public API changes. The writer currently rejects `.deflated` entries — it will instead compress them:

```swift
// Before: throws ZIPError.unsupportedCompressionMethod(8)
// After: compresses with Deflate and writes method 8
let entry = ZIPEntry(path: "data.xml", data: xmlData, method: .deflated)
let archive = try ZIPWriter.write(entries: [entry])
```

The default `CompressionMethod` remains `.stored` — existing callers are unaffected.

### Feature B: Modification Timestamps

Add an optional date to `ZIPEntry`:

```swift
public struct ZIPEntry: Sendable, Equatable {
    public let path: String
    public let data: Data
    public let method: CompressionMethod
    public let modificationDate: Date?

    public init(
        path: String,
        data: Data,
        method: CompressionMethod = .stored,
        modificationDate: Date? = nil
    )
}
```

Behavior:
- **Writer:** If `modificationDate` is non-nil, encode as MS-DOS time/date in the local and central directory headers. If nil, write the current date/time (not zero).
- **Reader:** Decode the MS-DOS time/date from headers and populate `modificationDate`. Archives with zero timestamps produce `nil`.

### Feature C: ZIP64

Internal implementation detail — no public API changes. The writer and reader automatically use ZIP64 structures when needed:

- Writer: emits ZIP64 extra fields and ZIP64 EOCD + locator when any entry's compressed/uncompressed size exceeds `0xFFFFFFFF`, or when entry count exceeds `0xFFFF`, or when the central directory offset exceeds `0xFFFFFFFF`.
- Reader: detects ZIP64 EOCD locator, reads ZIP64 EOCD, and reads ZIP64 extra fields from entries. Falls back to standard fields when ZIP64 is not present.

Internal size types change from `UInt32` to `UInt64` where needed.

### MS-DOS Time Encoding (internal)

```swift
enum DOSTime: Sendable {
    static func encode(_ date: Date) -> (time: UInt16, date: UInt16)
    static func decode(time: UInt16, date: UInt16) -> Date?
}
```

MS-DOS time format:
- Time: bits 15–11 = hours (0–23), bits 10–5 = minutes (0–59), bits 4–0 = seconds/2 (0–29)
- Date: bits 15–9 = year-1980 (0–127), bits 8–5 = month (1–12), bits 4–0 = day (1–31)
- Resolution: 2 seconds. Range: 1980-01-01 to 2107-12-31.

---

## 5. MCP Schema

Not applicable — SwiftZIP is a library dependency, not an MCP-exposed tool. Its consumers (SwiftXLSX) may expose MCP endpoints, but the ZIP layer is internal plumbing.

---

## 6. Constraints & Compliance

- **Concurrency:** All types remain Sendable. `Date` is Sendable. No mutable shared state.
- **Safety:** No force unwraps. Guard clauses for all ZIP64 field validation. Division safety not applicable (no division in ZIP format handling).
- **Zero dependencies:** Continues to use only Foundation + Compression framework.
- **Backwards compatibility:** All changes are additive. The new `modificationDate` parameter defaults to `nil`. Existing `.stored` callers are unaffected. ZIP64 is auto-detected.

---

## 7. Source & API Compatibility

**Breaking changes:** None.

- `ZIPEntry.init` gains an optional `modificationDate` parameter with a default value — existing call sites compile unchanged.
- `ZIPWriter.write(entries:)` accepting `.deflated` entries is a relaxation, not a restriction — code that previously caught the error will stop throwing.
- ZIP64 is entirely internal — the public API uses `Data` and `[ZIPEntry]` regardless.

**Incremental adoption:** Each feature is independently useful. A consumer can start using `.deflated` entries without caring about timestamps or ZIP64.

**Equatable impact:** Adding `modificationDate: Date?` to `ZIPEntry` means two entries with the same path/data/method but different dates are not equal. This is correct behavior — they represent different archive states.

---

## 8. Backend Abstraction

Not applicable. ZIP encoding/decoding is I/O-bound, not compute-bound. The Compression framework already handles the CPU-intensive Deflate work.

---

## 9. Dependencies

**Internal Dependencies:**
- `Deflate.compress` — already implemented, currently unused by writer
- `DataHelpers` — will be extended with UInt64 read/write
- `CRC32.calculate` — already used by writer

**External Dependencies:** None.

---

## 10. Test Strategy

### Feature A: Writer Deflate

**Test Categories:**
- Golden path: Write deflated entry, read back, verify data matches original
- Round-trip: Mixed stored + deflated entries survive write-read cycle
- Size verification: Deflated archive of XML content is smaller than stored archive
- Empty data: Deflated entry with empty data round-trips correctly
- Large data: 500KB+ entry compresses and decompresses correctly
- Interop: Archives written with deflated entries can be read by `/usr/bin/unzip`

**Reference Truth:** `/usr/bin/unzip -t` validates the archive structure. CRC-32 verification on read confirms data integrity.

**Validation Trace:**
- Write "Hello, World!" as deflated → read back → assert data equals `Data("Hello, World!".utf8)`
- Write 100KB of repeating XML → assert archive size < original data size
- Write deflated archive → run `unzip -t` → assert exit code 0

### Feature B: Modification Timestamps

**Test Categories:**
- Golden path: Write entry with known date → read back → verify date matches (to 2-second resolution)
- Nil date: Write entry with nil date → verify current time is written (not zero)
- Zero timestamp: Read archive with zero timestamps → verify `modificationDate` is nil
- Boundary dates: 1980-01-01 (minimum), 2107-12-31 (maximum), dates outside range
- Round-trip: Date survives write → read cycle within 2-second precision

**Reference Truth:** MS-DOS time format is specified in PKWARE APPNOTE.TXT section 4.4.6. Python's `zipfile` module uses the same encoding and can cross-validate.

**Validation Trace:**
- 2026-06-02 14:30:00 UTC → DOS time: `0x7500` (14h=1110_0, 30m=01111_0, 0s=00000), DOS date: `0x5CC2` (46y=010110_0, 6m=0110, 2d=00010)
- Encode then decode → assert result is within 2 seconds of input

### Feature C: ZIP64

**Test Categories:**
- Golden path: Archive with >65,535 entries uses ZIP64 EOCD and round-trips
- Large entry: Entry with size field = 0xFFFFFFFF triggers ZIP64 extra field
- Large offset: Central directory offset > 0xFFFFFFFF triggers ZIP64
- Backwards compatible: Archives below thresholds produce standard (non-ZIP64) format
- Reader: Parse ZIP64 archives produced by `/usr/bin/zip`
- Interop: ZIP64 archives written by SwiftZIP validate with `/usr/bin/unzip -t`

**Reference Truth:** PKWARE APPNOTE.TXT sections 4.3.14 (ZIP64 EOCD), 4.3.15 (ZIP64 EOCD locator), 4.5.3 (ZIP64 extra field). `/usr/bin/unzip -t` for structural validation.

**Validation Trace:**
- Write 65,536 entries (1 over UInt16 max) → verify ZIP64 EOCD present → read back → verify count == 65,536
- Note: Testing actual 4GB+ files is impractical in CI. We test the format logic with synthetic archives where size fields are set to 0xFFFFFFFF and ZIP64 extra fields carry the real values.

---

## 11. Architecture Decision Review

**ADR Check:**
- [x] Reviewed `architecture_decisions.md` for related decisions
- [ ] Does this supersede an existing ADR? No
- [ ] Does this amend an existing ADR? No
- [x] New ADR required? Yes — draft below

**New ADR Draft:**
- Title: Writer Deflate with automatic size-comparison optimization
- Category: api
- Key decision: The writer compresses with Deflate when `.deflated` is requested, but falls back to stored if the compressed output is larger than the original (which happens for small or incompressible data). This matches `/usr/bin/zip` behavior and avoids inflating tiny entries.

---

## 12. Adversarial Review

**Strongest case for a different approach:**
A reviewer might argue that ZIP64 is premature — SwiftZIP's stated use case is document formats (spreadsheets, docx), which will never hit 4GB or 65K entries. The implementation complexity and testing burden aren't justified by the use case.

Counter: The argument is sound for *adding new capabilities*, but the real value of ZIP64 is *preventing silent data corruption*. Today, writing 65,536 entries produces a corrupt archive with no error. ZIP64 replaces silent corruption with correct behavior. The implementation is mechanical (wider fields + extra records) rather than algorithmically complex.

**Where this design is most likely wrong:**
The assumption that `modificationDate: nil` should write the current time (not zero) could surprise callers who explicitly pass `nil` expecting "no timestamp." However, zero timestamps are malformed per the spec (month 0, day 0 don't exist in DOS date format), and writing the current time is what every other ZIP library does by default.

**What an experienced critic would say:**
"You're adding three features in one proposal — that's three independent risk surfaces." We're proceeding because all three are small, well-bounded changes to the same two files (writer + reader), and they share a test harness. They'll be implemented in three separate TDD cycles with independent commits, not as a single change.

---

## 13. Alternatives Considered

**Alternative 1: Always compress (ignore `.stored` preference)**
- Advantage: Simpler API — no method parameter needed, writer always picks the smaller output
- Disadvantage: Breaks existing behavior. Some consumers rely on stored entries for predictable offsets (e.g., appending to archives). Also prevents round-tripping: a stored entry read from an external archive would be re-compressed on write-back.
- Why rejected: Respecting the caller's explicit compression choice is more correct. The writer can still optimize internally (skip deflate if compressed size >= original).

**Alternative 2: Use `Extended Timestamp` extra field (0x5455) instead of DOS time**
- Advantage: Unix timestamps with 1-second resolution, timezone-aware
- Disadvantage: Not universally supported. Some tools only read DOS timestamps. The extended field adds bytes to every entry. DOS time is the baseline that all ZIP tools expect.
- Why rejected: DOS time is the mandatory field. We could add extended timestamps as a future enhancement, but the DOS fields must be populated regardless.

**Alternative 3: Skip ZIP64, add a size/count validation error instead**
- Advantage: Much simpler — just throw an error if limits are exceeded
- Disadvantage: Artificial limitation on a format that has a standard solution. Every other ZIP library supports ZIP64.
- Why rejected: Validation errors are the right interim step (and we'll add them first), but ZIP64 removes the limitation entirely. The format is well-specified and mechanical to implement.

---

## 14. Future Directions

- **Extended Timestamp extra field (0x5455)** could provide 1-second resolution timestamps alongside DOS time
- **Compression level parameter** could let callers trade speed for size (currently uses Compression framework defaults)
- **Streaming writer** could emit entries without buffering the entire archive in memory
- **`CompressionMethod.auto`** could let the writer choose the smaller of stored vs. deflated per entry

---

## 15. Open Questions

1. **Should nil `modificationDate` write current time or zero?** Proposed: current time. Zero is technically malformed (month 0, day 0). Callers who want reproducible archives can pass an explicit date.
2. **ZIP64 entry count test — is 65,536 entries practical in the test suite?** Each entry can be minimal (empty data, short path), so the test should complete in seconds. If too slow, we can test the format logic with a synthetic archive.
3. **Should we emit ZIP64 unconditionally or only when needed?** Proposed: only when needed, for maximum compatibility with older tools.

---

## 16. Documentation Strategy

**Documentation Type:** API Docs Only

**Complexity Threshold Check:**
- Does it combine 3+ APIs? No — the public API changes are minimal (one new parameter)
- Does explanation require 50+ lines? No
- Does it need theory/background context? No

The README usage examples should be updated to show `.deflated` and `modificationDate`, but no narrative article is needed.

---

## Implementation Order

The three features should be implemented in this order, each as a complete TDD cycle:

1. **Writer Deflate** — highest user-visible impact, `Deflate.compress` already works
2. **Modification Timestamps** — small, self-contained, no dependencies on Feature A
3. **ZIP64** — most complex, benefits from the writer already handling deflated entries

Each feature gets its own implementation checklist, commits at each green state, and quality-gate pass before moving to the next.
