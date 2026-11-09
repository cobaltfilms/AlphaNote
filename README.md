# AlphaNote

A macOS scratchpad app inspired by [Antinote](https://antinote.io) — ephemeral notes, always one keystroke away.

## Vision

AlphaNote is a scratchpad-first note app for macOS that prioritizes **the present moment** over organization.
It appears on demand via a global hotkey, lets you jot down temporary notes, perform calculations,
convert units/currencies, manage checklists, and run timers — all through fast text-driven workflows.

It is NOT a replacement for permanent note apps. It is the fast, disposable companion you reach for
between thoughts.

## Features

- **Global hotkey** (⌥A by default, recordable) — instant access from anywhere; Esc hides
- **Floating window** — stays on top, remembers its frame, follows the active Space
- **One editor for every mode** — `math`, `list`, `code` or `timer` on the first line just decorates the text; no focus loss
- **Live math** — variables, inline results, functions, percent, units, currencies (async rates)
- **Checklists** — click the margin to tick, `- ` bullets continue on Enter
- **Timers** — countdown / stopwatch / alarm at a given time, that survive note switches and relaunch
- **⌘K natural-language routing** — a JEV decision server *classifies* the request, local code applies it; keyword fallback shown on screen
- **Overlay note list** (⌥⌘L) with text + local semantic search, pins and archive
- **Local SQLite persistence** (debounced writes) + optional Nextcloud sync (ETag-aware)
- **In-app help center** (⇧⌘H) + full embedded guide

## Tech Stack

- Swift / SwiftUI + AppKit (macOS 14+)
- GRDB.swift (SQLite)
- swift-collections

## Documentation

- In app: `Help` > `AlphaNote Help` (shortcut `⌘⇧H`)
- Markdown guide: `Sources/AlphaNote/Resources/Docs/ALPHANOTE_HELP_FR.md`

## Build

```bash
swift build                      # debug binary (.build/debug/AlphaNote)
scripts/build-app.sh 1.2.0 --zip # AlphaNote.app + zip; CODESIGN_IDENTITY=... for a stable signature
```

## Test

```bash
swift test
```

## Run

```bash
swift run AlphaNote
```

## iOS (simulateur)

L'app iOS (`iOS/`, projet XcodeGen) compile directement le cœur macOS
(`Sources/AlphaNote`) ; seule l'interface vit dans `iOS/App`.

```bash
scripts/ios.sh run    # compile, installe et lance dans le simulateur
scripts/ios.sh test   # tests partagés + tests d'interface
```

## Open in Xcode

```bash
open Package.swift
```

## AI (optional)

AI features are **off by default**. The ⌘K routing talks to a JEV decision
server, which is not part of this repository; without it, AlphaNote uses the
on-device classifier and the keyword fallback. See `RESUME-IA.md` and `ml/`.

## Downloads & updates

Signed builds for macOS and Android are published in
[Releases](https://github.com/cobaltfilms/AlphaNote/releases). The apps check
`appcast.json` (macOS) and `appcast-android.json` (Android) on the `main`
branch of this repository — please keep these files at the root.

## Contributing

Development happens on Cobalt Films' own Git server; this GitHub repository is
a mirror of it. Issues and pull requests are welcome here: accepted changes are
applied upstream and come back through the mirror.

## License

Licensed under the [Apache License 2.0](LICENSE). Copyright 2026 Cobalt Films.
