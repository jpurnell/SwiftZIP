# Design Proposal: Gzip Member Reading

**Status:** Draft — awaiting review
**Master Plan Reference:** compression formats

---

## 1. Objective

Read a gzip member (RFC 1952) into `Data`, with integrity verified.

## 2. Motivation

**Current situation:** SwiftZIP reads the ZIP container. Gzip is a different format —
a single DEFLATE stream wrapped in a 10-byte header and an 8-byte trailer — and the
package cannot read one.

**Why here rather than a new package:** SwiftZIP already owns every piece except the
wrapper. `Deflate.decompress` handles the payload, `CRC32` verifies integrity, and
`CZlib` is already linked. A separate gzip package would duplicate all three and add a
second compression dependency to every consumer.

**What prompted it:** a consumer needed to read a 313 MB `.jsonl.gz` index natively.
Shelling out to `gunzip` would make a Swift product depend on a process; Foundation has
no gzip reader.

## 3. Proposed Architecture

```
Sources/SwiftZIP/GzipMember.swift    header/trailer parsing + public reader
```

Reuses `Deflate.decompress(_:uncompressedSize:)` and `CRC32`, both already present and
tested.

## 4. API Surface

```swift
public enum GzipMember {
    /// Decompresses one gzip member, verifying its CRC-32.
    public static func decompress(_ data: Data) throws -> Data

    /// Reads a file, decompressing only if it is gzipped.
    public static func read(contentsOf url: URL) throws -> Data

    /// Whether these bytes begin a gzip member.
    public static func isGzip(_ data: Data) -> Bool
}
```

## 5. MCP Schema

Not applicable.

## 6. Constraints & Compliance

**Integrity is verified, not assumed.** The trailer's CRC-32 is checked against the
decompressed bytes. Without it, corrupt DEFLATE returns plausible garbage and nothing
errors — which is precisely the failure a compression library must not permit.

**ISIZE is a hint, not a contract.** It records the uncompressed size **modulo 2³²**, so
it is wrong for members over 4 GB. It seeds the output buffer; the CRC decides
correctness.

**Optional header fields are parsed, not assumed absent.** FEXTRA, FNAME, FCOMMENT and
FHCRC are all optional and all shift the payload offset. `gzip -n` omits FNAME while a
plain `gzip` includes it, so a reader that assumes a fixed 10-byte header works on some
files and silently misreads others.

**Safety:** no force unwraps; every malformed shape returns a typed error.

## 7. Source & API Compatibility

Additive. No existing API changes.

## 8. Backend Abstraction

None new — inherits SwiftZIP's existing Compression-framework/zlib split.

## 9. Dependencies

None beyond what SwiftZIP already links.

## 10. Test Strategy

`GzipMember` is a **parser**, so §4b requires property-shaped tests.

| Property | Assertion |
|---|---|
| Round-trip | output of `/usr/bin/gzip` decompresses to the original, for varied content |
| Never traps | seeded generator over truncated, random and adversarial byte sequences |
| Corruption is caught | damaged payload fails the CRC rather than returning bytes |
| Header variants | `gzip -n` (no FNAME) and plain `gzip` (FNAME present) both read |
| Size independence | content far larger than any buffer guess still decodes fully |

Fixtures are produced by the **system `gzip`**, not by our own writer — a round-trip
against ourselves would pass even if our understanding of the format were wrong.

## 11. Architecture Decision Review

**Decision — verify the CRC.** A decompressor that cannot detect corruption is worse
than none, because its output looks valid.

## 12. Adversarial Review

**Strongest case against:** gzip in a package called SwiftZIP is scope creep, and a
consumer wanting gzip now drags in a ZIP reader it will never call.

**Response — partly conceded.** The name is a poor fit and will mislead. But the
alternative is worse: a separate package duplicating `Deflate`, `CRC32` and the `CZlib`
system target, leaving two compression libraries to keep in step. The honest resolution
is that this package is *about DEFLATE-based formats* and the name under-describes it;
renaming is a larger decision than this proposal should make. Recorded so the naming
question is deliberate rather than forgotten.

## 13. Alternatives Considered

| Alternative | Why not |
|---|---|
| A separate `GzipKit` | Duplicates Deflate, CRC32 and the CZlib target |
| Shell out to `gunzip` | Makes a Swift product depend on a process |
| Compression framework alone | Decodes raw DEFLATE only; no header, no CRC |

## 14. Future Directions

- Gzip **writing**, if a consumer needs it. Not speculatively.
- Multi-member gzip streams (concatenated members) — rare, and unneeded so far.

## 15. Open Questions

1. **Should the package be renamed** to reflect DEFLATE formats generally? (§12)
2. **Streaming?** The current API decompresses whole members; a 313 MB index is
   acceptable in memory, a 10 GB one would not be.

## 16. Documentation Strategy

DocC on the public API, noting the ISIZE modulo caveat explicitly — it is the kind of
detail that produces a rare, confusing bug when forgotten.


## Addendum — test fixtures are committed, not generated

The first draft generated each fixture by spawning `/usr/bin/gzip` inside the test.
Two things were wrong with that, and the quality gate caught the first:

1. **An unbounded child process in a test.** `Process()` + `waitUntilExit()` returns
   when the child exits *or never*, and nothing drained its pipes. `bounded-io`
   flagged both, correctly — a hung fixture would have hung the suite with no
   diagnostic.
2. **A dependency on the host's gzip.** The suite's result would have varied with
   whichever gzip the machine happened to ship.

The fixtures in `Tests/SwiftZIPTests/Fixtures/gzip/` are therefore produced once by
the system `gzip` and committed. This keeps the property that made spawning
attractive — the bytes come from a *reference implementation*, never from our own
writer, so a round-trip cannot pass by being consistently wrong — while removing
both the spawn and the host dependency.

`with-name.gz` carries an `FNAME` field and `no-name.gz` does not (`gzip -n`), so
the pair pins the variable-length header. A reader that assumed a fixed 10-byte
header would decode one and silently corrupt the other.

## Addendum — the DocC catalogue

`doc-code` compiles the Swift fences in documentation. Adding
`Sources/SwiftZIP/SwiftZIP.docc` surfaced that the first draft of the overview
documented an API that does not exist — an instance `ZIPReader(data:)` with
`.entries` and `.extract(_:)`, where the real type is a caseless enum of static
methods returning `[ZIPEntry]`. The fences now compile against the real surface.
