# Grove feedback from Flora

Observations from building Flora on Grove, 2026-10-10 through 2026-10-13.
Open items first — these are what we actually want next. The resolved
ledger at the bottom is the record of what already landed; the narrative
detail for each lives in git history and in the grove commit messages.

## Open

### Incremental analysis: every rebuild re-runs the whole analyze phase

The render side is properly incremental — 1 affected artifact means 1
re-render. The analysis phase is not: wall-clock per rebuild is roughly
flat regardless of what changed. Measured repeatedly on the flora tree
(grove `5f5606d`–`08df222`, shared stable cache):

- initial full build: 85–95 s;
- style.css only (1 affected artifact): 139–144 s to arrival;
- one `.plant` (1–8 affected): 137–140 s;
- a warm manual build with 0 affected: 114–122 s.

The floor is load + analysis + forest/relation assembly. Document-level
reuse inside analysis already exists ("Reused 1113/1122 document
results, Analyzed in 68.9 s"), so the building blocks are there; what is
missing is a fast path where artifact-only edits (stylesheets, scripts,
fonts) skip analysis wholesale by reusing the previous forest, and
per-document analysis keys that make a `.plant` edit re-analyze only
that document and its dependents. Edit-to-preview at ~140 s for a CSS
tweak is the one number that still hurts the writing loop.

First step landed in grove commit `d4980fc` (2026-10-14): `--profile`
(build, check, serve). It reports the input-cache cost split — every
document read booked to the reuse side (entry read, identity check,
dependency verification, unpack) or the fresh side, with counts and
seconds — the project file's own evaluation time as its own phase, and
the process's peak RSS (VmHWM). Serve passes the flag to its workers,
so the lines land on the serve terminal. A warm run on the flora tree
with this flag is the measurement the design decision needs: if the
reuse side dominates the floor, the cheap-hits path (mtime/size
pre-filter before content hashing) comes first; if unpacking
materialization dominates, forest-level reuse is the answer. Please run
and share: `grove build --profile` on a warm tree, twice.

Run and shared (2026-10-14, grove `d4980fc`, shared stable cache):

- fully warm, 0 affected: total 121.6 s — analyze 93.3 s, of which the
  input-cache reuse side is 25.1 s (1122 documents, ≈22 ms each: entry
  read, identity check, dependency verification, unpack) and the
  remaining ≈68 s is re-derivation — forest assembly, the reference,
  page, content-node, and term relations, the anchor index, query
  resolution — plus module evaluation. Peak RSS 509 MiB.
- module edit (`queries.plant` touched): 0 reused / 1122 fresh in
  48.8 s (≈43 ms per document of true re-analysis), analyze 57.3 s,
  18 affected artifacts, total 135.6 s.

The answer to the design question: the reuse side does not dominate the
floor — 25 s of reads against ≈68 s of re-derivation. Unpacking is not
where the time goes; materialization is. Forest-level reuse is the
first move: when the changed set contains no analysis-visible input
(every CSS/JS/font edit), reuse the previous forest wholesale and go
straight to render — that alone turns a CSS cycle into seconds. Cheap
hits are worth ≈20 of the 25 s of reads at best, second. A module edit
legitimately re-analyzing everything is correct semantics, and its
48.8 s is honest work.

### Relation rows should name the host article, not just the owning subtree: resolved upstream (grove commit `612de0d`, 2026-10-14)

An in-paragraph `defn` belongs to its subtree's own page id — an
anonymous `unstable-8` for unnamed subtrees. The term relation and its
reports are correct but unreadable without a lookup table: the drift
report reads `tree（树），本页口径（unstable-8）` and nothing tells you
which article that was. Ask: term-definition and mention rows (or at
least the report projections) carry the host article's page id — and
ideally its title — alongside the owning subtree. (Named subtrees are
the other half of the answer; grove cannot supply the discipline, but
the report can stop punishing its absence.)

Resolved in grove commit `612de0d` (2026-10-14): the report projections
resolve each occurrence up the composition graph — subtree definitions,
then transclusion inclusions — to its host article, and carry the
host's id and title beside the owning page. Shapes now:

- `(term-definition-conflicts forest)` → `(term-id (host-id host-title
  page-id anchor display-text) …)` — deep-link to
  `host.html#anchor` while naming the article; collection order keeps
  the canonical entry first.
- `(undefined-term-mentions forest)` → `(term-id (host-id host-title
  page-id) …)`.

The host table memoizes per forest; the relation-level conflicts
projection (outside a forest context) keeps `(page-id anchor
display-text)`.

Adopted in Flora same-day: `@term-conflicts` renders each occurrence as
a deep link into the owning page's own route (where the raw anchor
resolves — the host article's rendering prefixes anchors, so
`host.html#anchor` would not scroll) labelled with the host article's
title. The verified drift report now reads:

    tree：
      tree（树）（术语表：文档、文学编程与数学）→ /glossary-grove.html#tree
      tree（树），本页口径（用.plant写作：元数据、命令与Scheme）→ /unstable-8.html#tree

`unstable-8` still appears, but the report names the article beside it —
the lookup-table problem is gone. Backlog mentions link to the host
article too.

### `term-definition-conflicts` drops the anchor: resolved upstream (grove commit `612de0d`, 2026-10-14)

The facts hold `(term-id page-id anchor display-text)`, but the
conflicts projection yields `(term-id (page-id display-text) …)` — so a
drift report cannot deep-link to the definitions it is reporting. Keep
the anchor in the projection; the report (and anything built on it,
like Flora's `@term-conflicts`) can then link each occurrence to
`page#anchor` the way `@term-index` already does.

Resolved in grove commit `612de0d` alongside the host-article work: the
projection is `(page-id anchor display-text)` at the relation level and
`(host-id host-title page-id anchor display-text)` in the forest-level
report. `@term-conflicts` can link each occurrence the way
`@term-index` does.

Adopted same-day: `@term-conflicts` now deep-links every occurrence —
verified against the planted drift (see above); the report links
`/glossary-grove.html#tree` and `/unstable-8.html#tree` where it
previously could only name pages.

### Serve lifecycle suite under the blue test driver

Carry-over caveat from the build-lock work: under `blue check` the
spawned serve is a grandchild process where libgcrypt's hash call dies
with ENOSYS, so the serve lifecycle suite only runs as a direct serve
process on this machine. Everything it pins (lock queueing, shared
state, watch behavior) is nonetheless verified against the real flora
tree — see the ledger. Filed so the driver limitation is not forgotten
once the environment changes.

## Resolved ledger

Everything below landed in grove, was verified against this tree, and is
adopted by Flora. One line each; full narrative in history.

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
- `38cf57e` — serve names the changed paths that trigger each rebuild.
- `320c524`/`5d6d1ec`/`8dd2d1b` — backmatter entries as collapsible
  tree blocks: outline first, fetch-full on expand, source-tree naming.
- `5a023cb` — one project, one build lock; waits announce themselves.
- `69b015b` — stable workspace cache, orphan sweep behind a `.live`
  flock, watch first-sightings are not edits. Verified: no phantom
  rebuilds, no cache-N generations, single `cache/`, SIGTERM cleans up.
- `63532f6` — drift between build start and end invalidates the build
  state; quiet reverts heal immediately (9 affected, no manual build).
- `fda4c0a` — extra-sources fingerprinted pre-analysis; the mid-build
  revert window closed (probe cycle 1 affected, revert cycle forces the
  full re-render, output heals). One full render is the correct price.
- `02f0362` — serve and manual builds share the per-project state under
  `$XDG_CACHE_HOME/grove/<hash>`; workspaces hold no cache anymore.
  Verified both directions at 0 affected on the real tree.
- `465fa08` + `5f5606d` — missing project file names the directory and
  `--project`; project discovery walks upward git-style.
- `79b9688` — page definition contract documented; bare top-level
  `@(define …)` in pages no longer needs the `begin` splice.
- `d13f423` — `content->plain-text` public in `(grove ir)`; Flora's
  `fragment-text` duplicate deleted.
- `4597d67` — `make-element` `#:kind`; Flora's sidenote is back on the
  public API (`#:tag "span" #:class "flora-sidenote" #:kind
  'flora-sidenote`).
- `372f204` — the build lock no longer lives in the deployable output.
- `4a60360` — `#:side-lane` lifts margin-note kinds into a page-level
  lane at render time; Flora's theme.js relocation retired, the article
  is a subgrid across the reading and notes lanes, CSS counters agree
  with the renderer's markers, narrow viewports fold the lane into an
  endnote group.
- `dd0a5dd` — term-definition and term-mention relations with
  `term-definitions`/`term-definition-conflicts`/
  `undefined-term-mentions`; Flora's `/glossary` group 1 is defn-backed
  and `/queries` carries the generated `@term-index` and
  `@term-conflicts`.
- `08df222` — marked term mentions resolve against the definition
  relation (raw anchors, canonical display, body override, missing-term
  fallback, backlog with resolution state); Flora's `@term` command
  emits a `query-link` with a `term` property — plain `link` would fail
  reference validation, which a mention cannot satisfy at authoring
  time.
