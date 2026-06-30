# Whitespace — Feature & Usage Guide

Whitespace turns your macOS desktop into a native, Excalidraw-style whiteboard.
This guide covers everything it can do and how to use it.

---

## Install & launch

```bash
swift build            # or: open Package.swift in Xcode
./make_app.sh          # assembles Whitespace.app (release build, ad-hoc signed)
cp -R Whitespace.app /Applications/
open -a Whitespace
```

Whitespace is a **menu-bar app** (no Dock icon). It appears as a scribble icon in
the status bar, and its canvas lives on the **desktop layer** — above your
wallpaper, behind your icons.

---

## Core concept: Edit Mode

The desktop can't both "be the wallpaper" and "capture your clicks" at once, so
there's an explicit **Edit Mode**:

| Mode | What happens |
|------|--------------|
| **Idle** | Drawings show through on the desktop; clicks pass to your icons/Finder as normal. |
| **Edit** | The board captures the mouse; the floating tool palette appears; you draw. |

- Toggle Edit Mode: **⌥⌘W** (or menu-bar → *Start/Stop Drawing*). By default your
  drawings stay on the wallpaper when you exit; set **gear → When hidden → Hide
  everything** to make ⌥⌘W clear the whole canvas instead.
- Show/hide just the palette while editing: **⌥⌘Q**.
- Edit Mode opens on whichever **display** your cursor is on.

---

## Tools

Pick a tool from the palette or press its key. The current tool stays selected
(it doesn't snap back to the cursor).

| Key | Tool | |
|-----|------|--|
| `V` | Select | move, resize, rotate, marquee-select |
| `H` | Hand | pan the canvas |
| `R` | Rectangle | |
| `O` | Ellipse | |
| `D` | Diamond | |
| `A` | Arrow | connects + binds to shapes |
| `L` | Line | |
| `P` | Freedraw | freehand |
| `T` | Text | |
| `E` | Eraser | click/drag to delete |

**More tools** (the `…` menu in the palette):

- **Frame** (`F`) — a labeled container; move the frame and its contents move with it.
- **Laser pointer** (`K`) — a red trail for presenting; it fades after you release.
- **Lasso** (`Q`) — freeform selection; draw a loop around elements.
- **Code Cell** — a runnable code node (see [Live cells](#live-cells)).
- **Run Graph** — execute connected cells (⌘⇧↵).

---

## Styling (the inspector)

With a tool or selection active, the inspector shows what applies:

- **Stroke** & **Background** color swatches
- **Fill**: hachure · cross-hatch · solid · zigzag
- **Stroke width** and **Stroke style**: solid · dashed · dotted
- **Sloppiness**: Architect · Artist · Cartoonist (the rough.js hand-drawn feel)
- **Edges**: sharp · round (rectangles)
- **Opacity**
- **Arrow type** (straight / elbow) and **Arrowheads** (none/arrow/triangle/dot/bar)
- **Font** and **Text size** (text *and* file/link nodes)

The currently-selected option is highlighted in purple.

---

## Selecting, moving, arranging

- **Select**: click; **marquee** by dragging on empty canvas; **Lasso** (`Q`) for a freeform loop; **⌘A** selects all.
- **Move**: drag. **Resize**: drag a handle. **Rotate**: drag the top knob.
- **Group / ungroup**: **⌘G** / **⌘⇧G** — a grouped element selects and moves as a unit.
- **Align & distribute**: select 2+ elements → the **Align** row appears (left/center/right/top/middle/bottom, distribute H/V).
- **Z-order**: the bottom bar's four buttons — bring to front / forward / backward / send to back.
- **Delete**: ⌫. **Undo/redo**: ⌘Z / ⌘⇧Z.
- **Clear board**: the *Clear* button (bottom-left of the palette).

---

## Connectors that stay attached

Draw an **arrow** (`A`) starting on one shape and ending on another and it
**binds** to both. Move either shape and the arrow re-routes to follow — your
diagram stays wired.

---

## Text

- **Free text**: pick `T` and click, or double-click empty canvas.
- **Label inside a shape**: double-click a rectangle/ellipse/diamond — the text
  centers and wraps to the shape.
- Choose any **font** and **size** in the inspector. 10 macOS fonts are bundled.

---

## Files, folders & links (Finder integration)

**Drag a file or folder from Finder onto the board** to link it. How a linked
node looks is set by **gear → File links**:

- **Preview** (default) — a card with the real **QuickLook thumbnail** (PDF page,
  doc preview, app icon), filename, and modified date; a red **Missing** badge if
  the file moves or is deleted.
- **Icon + name** — a compact 📄/📁 node.
- **Colored text** — a clean underlined link.

You can also add links from the palette **paperclip** menu: *Link File or Folder…*
and *Link URL…*

On a selected file/image node:

- **Space** — Quick Look (the native macOS preview panel).
- **Right-click** — Open · Quick Look · Reveal in Finder.
- **Double-click** — opens the file/URL.

> Note: Space pans the canvas normally, but Quick-Looks when a file/image node is selected.

**Images**: drag in an image file (or palette → image button) to place it; resize like any shape.

---

## Frames

Use **Frame** (`…` menu or `F`) to draw a labeled container. Anything drawn inside
or dragged into a frame becomes a member; **move the frame and its contents move
with it**. Frames sit behind their contents so children stay clickable.

---

## Boards (tabs)

The palette's tab bar manages multiple boards:

- **New**: the `+` button. **Switch**: click a tab.
- **Rename**: click the pencil (or right-click → Rename).
- **Reorder**: drag a tab.
- **Close**: the `×` (or right-click → Delete).
- **Export this board**: right-click a tab → *Export as PNG/SVG*.

Every board **autosaves** and persists on your desktop across relaunches.

---

## Import & export

- **Export** the current board: menu-bar → *Export as PNG/SVG…*, or right-click a tab.
- **Import** an `.excalidraw` file: drag it onto the board, menu-bar → *Open
  .excalidraw…*, or `open -a Whitespace file.excalidraw`. Everything reads/writes
  the **`.excalidraw`** format, so it round-trips with Excalidraw itself.

---

## Live cells

Shapes that **run code**. A cell holds source in a chosen language; run it and the
output renders in a panel beneath the code.

**Create**: palette `…` menu → **Code Cell** → Shell / Python / JavaScript / Ruby.
A cell drops in with starter code.

**Edit**: double-click the cell to edit its source (a monospaced editor; full
copy/paste/undo). Click off to commit.

**Run**:

- **⌘↵** — run the selected cell.
- Click the green **▶** in the cell header.
- **⌘⇧↵** (or `…` → *Run Graph*) — run every cell in dependency order.

### Arrows as live pipes

Draw an **arrow from one cell to another** and it becomes a **live data pipe** —
a glowing animated connector. When the graph runs, the upstream cell's output is
piped into the downstream cell's **stdin**, and a **pulse travels the pipe** as
data passes. Move a cell and the pipe follows.

Reading the piped input downstream:

| Language | Read the input with |
|----------|---------------------|
| Shell | `"$IN"` |
| Python | `sys.stdin` |
| JavaScript (Node) | `require('fs').readFileSync(0,'utf8')` |
| Ruby | `$stdin.read` |

> Cells run your own code on your machine, only from an explicit Run action —
> never automatically on load.

A worked example ships in the repo: `--build-arch <dir>` writes a runnable
**Live-Architecture** `.excalidraw` (a tiered system diagram whose monitoring
cells compute p50/p95/error-rate and decide a health verdict).

---

## Settings (palette gear)

- **When idle / When editing** — board backdrop: transparent · light wash · solid white.
- **When hidden (⌥⌘W)** — *Stay on wallpaper* (drawings remain on the desktop) or
  *Hide everything* (⌥⌘W clears the canvas to a clean desktop; ⌥⌘W brings it back).
- **Link color** and **File links** style (preview/icon/text).
- **Keyboard Shortcuts…** — remap the Edit-Mode and palette hotkeys.

---

## Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| ⌥⌘W | Toggle Edit Mode (show/hide the board) |
| ⌥⌘Q | Show/hide the tool palette |
| `V H R O D A L P T E` / `F K Q` | Select tools |
| ⌘G / ⌘⇧G | Group / ungroup |
| ⌘A | Select all |
| ⌘C / ⌘X / ⌘V | Copy / cut / paste |
| ⌘Z / ⌘⇧Z | Undo / redo |
| ⌫ | Delete selection |
| Space (hold) | Pan — or Quick Look a selected file/image node |
| ⌘-scroll / pinch | Zoom |
| ⌘↵ | Run the selected cell |
| ⌘⇧↵ | Run the whole cell graph |
| Esc | Deselect |

---

## Dev / verification harnesses

Headless flags for rendering and tests (used in development):

- `--export-test <dir>` — render a sample scene to PNG/SVG.
- `--run-cell-test <dir>` — execute sample cells and render them.
- `--build-arch <dir>` — generate the Live-Architecture `.excalidraw` + preview.

See [`docs/LIVE_CELLS_PLAN.md`](LIVE_CELLS_PLAN.md) for the live-cells roadmap.
