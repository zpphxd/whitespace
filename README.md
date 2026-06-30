# Whitespace

Turn your macOS desktop into an interactive, Excalidraw-style whiteboard — native,
written in Swift. Drawings live on the desktop layer (above the wallpaper), and a
glass tool palette appears when you're drawing.

## Features

- **Desktop-layer canvas** — a borderless `NSWindow` pinned to the desktop; toggle
  drawing mode on/off with **⌥⌘W**.
- **Faithful hand-drawn look** — the rough.js sketchy aesthetic re-implemented in
  pure Swift (seeded jitter, hachure/cross-hatch fills, ellipse curve sampling).
- **Tools** — select, rectangle, ellipse, diamond, arrow, line, freehand pen, text.
- **Style controls** — stroke/background color, fill style, stroke width, roughness
  (Architect/Artist/Cartoonist), text size.
- **Liquid Glass palette** — native macOS 26 `glassEffect`, docked left (**⌥⌘Q**
  hides/shows it).
- **Excalidraw-compatible** — reads and writes the `.excalidraw` JSON format;
  autosaves to `~/Library/Application Support/Whitespace/`.

## Build & run

Requires Xcode 26 / Swift 6 on macOS.

```bash
swift build && .build/debug/Whitespace      # quick dev run
./make_app.sh                               # build Whitespace.app (release)
```

`make_app.sh` produces a Dock-less (`LSUIElement`) `Whitespace.app` you can move to
`/Applications` and launch from Spotlight.

## Architecture

Fully native — no web view, no Electron.

- `App/` — desktop window, menu-bar control, global hotkeys, settings.
- `Canvas/` — `CanvasView` (Core Graphics), camera/pan-zoom, tools, interaction.
- `Model/` — Excalidraw-compatible `Element`/document, scene state, undo.
- `Rough/` — Swift port of the rough.js renderer + hachure fill.
- `Render/` — element renderer with a per-element CGPath cache.
- `UI/` — SwiftUI tool palette + Liquid Glass.
