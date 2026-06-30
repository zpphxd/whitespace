# Live Cells + Data → Charts — Build Plan

Branch: `feat/live-cells`

Turn Whitespace from "Excalidraw on the desktop" into a **spatial, living notebook**:
shapes that execute code, and data that flows along the arrows you draw.

## Concept

- **Cell node** — a node whose `text` is source code and `cellLanguage` selects an
  interpreter. Run it (⌘↵ / ▶) and its `cellOutput` renders in an attached panel.
- **Arrows are pipes** — connect cell A → cell B and A's output becomes B's input
  (`$IN` / stdin). The board is a visual dataflow graph.
- **Reactive recompute** — editing an upstream cell re-runs everything downstream
  along the bindings, spreadsheet-style.
- **Data nodes** — drop a CSV/SQLite → a **table node**; wire it into a **chart
  node** (native Swift Charts). Formula cells reference other nodes.

Security: cells run the user's own code, only from an explicit Run action, never
on load. Boards that contain cells show a visible "executable" badge.

## Data model (done in Phase 1)

`Element` gains (Whitespace extension to the Excalidraw schema, decoded leniently):
- `cellLanguage: String?` — `shell` | `python` | `javascript` | `ruby`
- `cellOutput: String?` — last captured combined stdout/stderr
- (`text` holds the source.)

New element `type`s: `cell` (done), later `table`, `chart`.

## Architecture

- `Compute/CellRunner.swift` (done) — launches the interpreter via `Process`,
  feeds source on stdin, folds stderr into stdout, returns `(output, failed)`.
  `runSync` for headless/off-main; `run` dispatches + completes on main.
- `Compute/DataFlow.swift` (Phase 3) — topological evaluator over the
  `startBindingId`/`endBindingId` arrow graph; pipes upstream `cellOutput` into
  downstream stdin; detects cycles; recomputes the dirty subgraph.
- `Compute/DataSource.swift` (Phase 4) — parse CSV / query SQLite into a
  `Table` (columns + rows); feeds table + chart nodes.
- `Render/ElementRenderer` — `drawCell` (done), later `drawTable`, `drawChart`.

## Phases

- **Phase 1 — Foundation (DONE).** Model fields; `CellRunner` (shell/python/js/ruby);
  IDE-style `drawCell` (header + language + ▶ + source + output panel);
  `--run-cell-test` harness (verified: shell/python/node execute and render).
- **Phase 2 — In-canvas cell UX.** A "Cell" tool / palette button to drop a cell;
  double-click to edit source in a monospaced field; ⌘↵ or click ▶ to run
  (async `CellRunner.run`, spinner while running, red tint on failure); resize.
- **Phase 3 — Arrows as pipes + reactivity.** Bind cell→cell; evaluator pipes
  output→stdin; "Run graph" runs in topo order; upstream edit marks downstream
  stale; cycle guard.
- **Phase 4 — Data → tables → charts.** Drop CSV/SQLite → `table` node; `chart`
  node (bar/line/scatter via Swift Charts) bound to a table or a cell's stdout
  (expects JSON/CSV); formula cells (`=SUM(node)`).
- **Phase 5 — Polish.** Per-board "executable" badge + opt-in; run-all / clear-all;
  export a board as a runnable `.excalidraw` (round-trips the new fields);
  timeouts + output truncation; language auto-detect.

## Verification

- Headless: `--run-cell-test <dir>` runs cells and renders `cells.png`.
- Later: `--render-table`, `--render-chart` harnesses; round-trip a board with
  cells through save/load to confirm the new fields persist.
