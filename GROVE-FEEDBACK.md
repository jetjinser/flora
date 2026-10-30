# Grove feedback from Flora

Observations from building Flora on Grove, 2026-10-10 through 2026-10-15.
Open items first. The ledger at the bottom records what already landed;
narrative detail lives in git history and the grove commit messages.

## Open

### Serve rebuild after document changes still requires full analysis

The last profile (2026-10-16) measured a fresh project load at ~10 s and
full re-derivation at ~68 s. Grove later added retained-model rebuilds
for changes outside analysis inputs, so asset-only edits can skip that
work. Document and analysis-input changes still require a fresh analysis;
re-measure this path before pursuing finer-grained invalidation.

For reference, the `--profile` numbers that chose forest-level reuse
over cache-read tuning (grove `d4980fc`, warm tree, 0 affected): total
121.6 s — analyze 93.3 s, of which input-cache reads are only 25.1 s
(1122 documents, ≈22 ms each) and ≈68 s is re-derivation: forest
assembly, the reference/page/content-node/term relations, the anchor
index, query resolution. Unpacking is not where the time goes;
materialization is. A module edit re-analyzing all 1122 documents takes
48.8 s (≈43 ms each) — correct semantics, honest work.

## Resolved ledger

- Serve lifecycle suite runs under Blue again (2026-10-29): `blue verify`
  completed tests, lint, and examples; targeted `blue check
  tests/unit/grove/serve.scm` passed locally. The prior grandchild-process
  ENOSYS limitation no longer applies. A parallel run exposed a test race:
  the neighboring-file assertion could run before the runtime-input rebuild
  settled. The test now waits for the watcher idle signal before editing the
  neighbor.

- Preview model reuse — Grove `9b5979b` and `c23603e`: watcher roots now
  follow collected documents and declared dependencies instead of
  recursively observing module-resolution candidates. Asset-only changes
  can reuse the retained model; changes to documents and analysis inputs
  still trigger fresh analysis. This supersedes the 2026-10-16 observation
  that stylesheet edits always invalidated Flora's retained model.

- Asset pipelines — grove `7f8beaa`: the `blazek2005-figures` pipeline
  replaced `regenerate-figures.sh`; figures re-crop only when the PDF,
  the manifest, or the pipeline changes, survive store sharing across
  checkouts, and retire cleanly from the build when the manifest drops
  them (verified 2026-10-16: add/remove cycle on `fig-x-test`, cold
  store 79.5 s for 1938 artifacts, warm rebuilds hit the index).
- Presentation hooks (`#:html-attributes`, `#:head`, `#:site-nav`,
  `#:home-link`, `#:title-decoration`, `#:article?`,
  `#:backmatter-details?`) — Flora no longer rewrites rendered markup.
- Backmatter Context lists the owning tree for standalone subtree pages
  (2026-10-10, verified on `blazek2005-front-ack.html`).
- `f60c61a` — script/style contents serialize as raw text; fixed the
  `SyntaxError` that killed the backmatter runtime site-wide.
- `384234e` — `#:flow-kind` passes through; childless elements close
  explicitly; serializer stopped emitting script contents twice.
- `e34cd60` — `page-taxon`/`page-tags`; `#:title-decoration` takes
  `(forest page)`.
- `998f3d6` — vanished paths tolerated in cache pruning and stale
  cleanup; `98e1252` — backlink lookups indexed.
- `320c524`/`5d6d1ec`/`8dd2d1b` — backmatter entries as collapsible
  tree blocks: outline first, fetch-full on expand, source-tree naming.
- `5a023cb` — one project, one build lock; waits announce themselves.
- `38cf57e` — serve names the changed paths that trigger each rebuild.
- `69b015b` — stable workspace cache, orphan sweep behind a `.live`
  flock, watch first-sightings are not edits.
- `63532f6` + `fda4c0a` — build state invalidated when sources drift
  (quiet reverts and the mid-build window, pre-build snapshot as the
  baseline); verified: revert cycles heal with no manual build.
- `02f0362` — serve and manual builds share the per-project state under
  `$XDG_CACHE_HOME/grove/<hash>`; verified 0 affected both directions.
- `926826b` + `8ef134c` — document analyses in a machine-global content
  store (`GROVE_STORE_DIR`); two checkouts of one project share (second
  checkout: 0 fresh, byte-identical artifacts).
- `d4980fc` — `--profile`: input-cache cost split, project-evaluation
  phase, peak RSS, on build/check/serve.
- `6423869` + `8d4a5a9` — analysis model exposed; resident serve worker
  renders from the retained forest, skipping analysis for asset edits
  (verified: CSS cycle ~140 s → 32–48 s, no analyze phase). Churn and
  the render floor remain — see the open item above.
- `465fa08` + `5f5606d` — missing project file names the directory and
  `--project`; project discovery walks upward git-style.
- `79b9688` — page definition contract documented; bare top-level
  `@(define …)` in pages no longer needs the `begin` splice.
- `d13f423` — `content->plain-text` public in `(grove ir)`.
- `4597d67` — `make-element` `#:kind`; Flora's sidenote back on the
  public API.
- `372f204` — the build lock no longer lives in the deployable output.
- `4a60360` — `#:side-lane` lifts margin-note kinds into a page-level
  lane at render time; Flora's theme.js relocation retired, the article
  is a subgrid across the reading and notes lanes, CSS counters agree
  with the renderer's markers, narrow viewports fold the lane into an
  endnote group.
- `dd0a5dd` — term-definition and term-mention relations with
  `term-definitions`/`term-definition-conflicts`/
  `undefined-term-mentions`; `/glossary` group 1 is defn-backed and
  `/queries` carries the generated `@term-index` and `@term-conflicts`.
- `08df222` — marked term mentions (`term` property) resolve against
  the definition relation: raw anchors, canonical display, body
  override, missing-term fallback, backlog with resolution state;
  Flora's `@term` emits a `query-link` — plain `link` would fail
  reference validation, which a mention cannot satisfy at authoring
  time.
- `612de0d` — term report projections carry the host article (id and
  title) and the anchor; the drift report deep-links to
  `page.html#anchor` while naming the article (`unstable-8` now reads
  「用.plant写作：元数据、命令与Scheme」), and backlog mentions link to
  the host too.
