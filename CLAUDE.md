# SwiftZIP — Pure Swift ZIP Reader/Writer

Zero-dependency Swift library for reading and writing ZIP archives.

## Key Rules

- No force unwraps (`!`), no `try!`, no force casts (`as!`)
- Zero external dependencies — Foundation + Compression framework only
- All public APIs require DocC documentation
- All types must be Sendable

## Quality Gate

`swift build && swift test` — zero warnings, zero failures.
