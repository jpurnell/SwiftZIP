# Design Proposal: One Error Vocabulary

**Status:** Approved for 0.7.0
**Created:** 2026-09-19
**Scope:** Breaking change to the public error surface; no behaviour change

---

## 1. Objective

Collapse three public error types into one, so a caller that uses ZIP *and* gzip *and*
zlib writes one `catch` and switches over one vocabulary.

---

## 2. Motivation

The package grew a second and third container over the same DEFLATE engine, and each
arrived with its own error enum. The three do not agree:

| `ZIPError` (top level) | `GzipMember.Failure` | `ZlibStream.Failure` |
|---|---|---|
| `truncatedArchive` | `tooShort` | `tooShort`, `truncated` |
| `invalidSignature` | `notGzip` | `notZlib` |
| `checksumMismatch(path:expected:actual:)` | `checksumMismatch(expected:actual:)` | — |
| `deflateError(String)` | `unsupportedMethod(UInt8)` | `inflateFailed(Int32)` |
| `missingEndOfCentralDirectory` | `malformedHeader` | — |

Two nested types share the name `Failure`. `checksumMismatch` carries `path` in one and
not the other, so the two cannot be handled by one branch. The same condition — input
ends early — is spelled three ways.

This is the moment to fix it. The next tag after this one is the last before 1.0, and
1.0 freezes the vocabulary: unifying it afterwards costs a major version.

---

## 3. Design

A single `ZIPError`, seven cases:

```swift
public enum ZIPError: Error, Equatable, Sendable {
    case truncated
    case invalidSignature
    case malformedHeader
    case missingEndOfCentralDirectory
    case unsupportedCompressionMethod(UInt16)
    case checksumMismatch(path: String?, expected: UInt32, actual: UInt32)
    case decompressionFailed(String)
}
```

**Why no `container` payload.** The obvious alternative carries which format failed
(`case truncated(Container)`). It is redundant: the caller knows whether it invoked
`ZIPReader.read`, `GzipMember.decompress`, or `ZlibStream.inflate`. The call site
already names the container, so the error does not have to.

**Why `path` becomes optional.** A ZIP entry has a path to report; a bare gzip member
does not. Optional is honest, and it keeps one `checksumMismatch` instead of two.

**Why the name `ZIPError` stays.** It is the established public name, the package is
called SwiftZIP, and consumers already catch it. That the package now reads two
non-ZIP containers is noted in the master plan and is not worth a rename on top of a
vocabulary change.

### Mapping

| Was | Becomes |
|---|---|
| `ZIPError.truncatedArchive` | `.truncated` |
| `ZIPError.deflateError(s)` | `.decompressionFailed(s)` |
| `ZIPError.checksumMismatch(path: p, …)` | `.checksumMismatch(path: p, …)` — `p` now `String?` |
| `GzipMember.Failure.tooShort` | `.truncated` |
| `GzipMember.Failure.notGzip` | `.invalidSignature` |
| `GzipMember.Failure.unsupportedMethod(m)` | `.unsupportedCompressionMethod(UInt16(m))` |
| `GzipMember.Failure.malformedHeader` | `.malformedHeader` |
| `GzipMember.Failure.checksumMismatch(e, a)` | `.checksumMismatch(path: nil, expected: e, actual: a)` |
| `ZlibStream.Failure.tooShort`, `.truncated` | `.truncated` |
| `ZlibStream.Failure.notZlib` | `.invalidSignature` |
| `ZlibStream.Failure.inflateFailed(c)` | `.decompressionFailed("zlib inflate failed: \(c)")` |

`inflateFailed`'s typed `Int32` is folded into the message, matching what
`deflateError(String)` already did at six of the eleven ZIP throw sites.

---

## 4. Compatibility

Breaking, and deliberately so at 0.x. Consumers catching `GzipMember.Failure` or
`ZlibStream.Failure` must catch `ZIPError`. Pattern matches binding
`checksumMismatch`'s path now bind `String?`. Construction with a non-nil path is
unchanged.

SwiftXLSX, the only known consumer, pins `from: "0.6.0"` and so must opt in; it does
not catch either nested type.

---

## 5. Out of scope

Error *messages* and `LocalizedError` conformance. The cases are the contract; prose
is not, and adding it later is additive.
