# AlphaNote

A macOS scratchpad app inspired by [Antinote](https://antinote.io) — ephemeral notes, always one keystroke away.

## Vision

AlphaNote is a scratchpad-first note app for macOS that prioritizes **the present moment** over organization.
It appears on demand via a global hotkey, lets you jot down temporary notes, perform calculations,
convert units, set timers, and OCR text from images — all through natural language typing.

It is NOT a replacement for permanent note apps. It is the fast, disposable companion you reach for
between thoughts.

## Features

- **Global hotkey (⌥A)** — instant access from anywhere
- **Floating overlay window** — stays on top, out of the way
- **Swipe navigation** — fluid note switching
- **Keyword modes** — plain text, math (`=`), checklists, code, timers
- **Live math evaluation** — safe recursive-descent parser, colloquial percent, variables
- **Unit & currency conversion** — distance, mass, temp + live exchange rates
- **SQLite-backed** — local-first, no cloud dependency

## Tech Stack

- Swift / SwiftUI + AppKit (macOS 14+)
- GRDB.swift (SQLite)
- swift-collections
- Apple Vision (OCR)

## Build

```bash
swift build
```

## Test

```bash
swift test
```

## Run

```bash
swift run AlphaNote
```

## Open in Xcode

```bash
open Package.swift
```

## License

Proprietary — Cobalt Films