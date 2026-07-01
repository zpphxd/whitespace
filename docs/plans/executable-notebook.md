# Executable Notebook — combining Excalidraw + Jupyter

> Status: **parked / concept.** Design locked, not yet started.
> Reference: https://github.com/jupyter/notebook

## Where each tool stops

- **Excalidraw** — beautiful spatial expression (draw an architecture, a pipeline,
  a test plan) but inert: no execution, no state, no data. The diagram never
  becomes the system.
- **Jupyter** — real execution with a **persistent kernel** (variables live across
  cells), rich outputs (plots, tables, HTML), an execution protocol. But it's
  **1-D**: a linear scroll of cells. No topology, no branching data flow.
- **Whitespace today (~⅓ there)** — cells run real code (`python3 -c`, `node -e`,
  …), **arrows are Unix pipes** (upstream stdout → downstream stdin + `$IN`), and
  **Run Graph** does a topological sweep of the cell/arrow DAG. This is a *spatial
  dataflow notebook* — already better than Jupyter for architecture/testing, worse
  for exploration (no shared state, text-only output).
  - Engine: `Sources/Whitespace/Compute/CellRunner.swift` (one-shot `Process` per
    run, code via `-c`/`-e` so stdin is free), plus `runGraph` / `topoSort` /
    `runGraphStep` in `CanvasView.swift`.

## Thesis

**A spatial, executable notebook**: draw the architecture, then *run* it. Two
execution models on one canvas:

1. **Dataflow mode** (have, to enrich) — each cell a pure function/service; edges
   carry typed data. Best for **architecture + testing**: run-graph = integration
   test, cells mockable or real, watch data flow the pipes.
2. **Session mode** (the Jupyter leap) — a group of cells shares a **persistent
   kernel**, so state accumulates like a real notebook. Best for **exploration /
   building** a component before wiring it in.

The same cell can live in either mode. That duality is the whole idea. The
endgame: **inference & agents** are the same primitive — an LLM cell is a cell
whose interpreter is a Claude call; an agent cell is a tool-using loop; edges
carry prompts/context/tool-results. Draw an agent DAG and run it.

## Architecture (pieces to build)

- **Kernels & state** — move from one-shot `Process` to **long-lived interpreter
  sessions** with a shared namespace. Cells get an execution count + status
  (idle/running/ok/error), like Jupyter's `[3]:`.
- **Typed edges** — pipes evolve from raw stdout strings to typed payloads
  (text / JSON / table / bytes), enabling **reactive** downstream re-run
  (Observable-style).
- **Rich outputs (MIME)** — render output bundles in-cell: text, **tables**,
  **charts** (reuse the existing chart engine), images, HTML/JSON.
- **Cell taxonomy** — code, **assertion/test** (green/red), markdown/doc, and later
  **LLM**, **agent**, **retrieval** cells.
- **Inference & agents** — LLM cell (Claude), agent cell (tool loop), retrieval
  cell; context-carrying edges; the canvas becomes a visual agent-DAG that runs.

## Phased roadmap

- **P0 (done)** — dataflow cells, pipe edges, topo run-graph.
- **P1 — Kernels & state**: persistent interpreter sessions, shared namespace,
  exec counts + status, reactive downstream re-run.
- **P2 — Rich outputs**: MIME rendering in-cell (tables, charts, images, HTML).
- **P3 — Architecture & testing**: assertion cells, mock/real toggle,
  run-graph-as-integration-test, failure highlighting on the canvas.
- **P4 — Inference & agents**: LLM cell, agent cell, retrieval cell;
  context-carrying edges; run the agent DAG.
- **P5 — Interop**: `.ipynb` import/export (linear ↔ spatial), optional real
  Jupyter-kernel backend for full Python richness.

## Locked decisions

- **Kernel model:** *roll our own persistent sessions* (long-lived interpreter
  processes we control; shared namespace via our own REPL protocol). Lighter, no
  heavy deps, we own the UX. Revisit real Jupyter kernels only if richness demands.
- **Execution scope:** run through **all five phases** end to end.
- **Branch:** do it on a **new branch** — it's a concept/experiment, kept off the
  mainline until proven.
- **Working style (granted):** proceed autonomously through the phases and ping
  when done.

## Pick-up checklist (when un-parking)

1. New branch, e.g. `feat/executable-notebook`.
2. P1: persistent-session runner (start with Python + shell), shared namespace,
   status/exec-count on the cell model + renderer.
3. P2: MIME output model on the cell; render tables/charts/images/HTML in-cell.
4. P3: assertion cell type + canvas failure highlighting.
5. P4: LLM/agent/retrieval cell types; context edges; agent-DAG run.
6. P5: `.ipynb` import/export.
