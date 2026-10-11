# Grove feedback from Flora

Observations collected while improving Flora's documentation. Each item is a
candidate change to Grove, not to Flora.

## Implemented in Grove

The HTML renderer now exposes presentation hooks, so Flora no longer rewrites
rendered markup:

- `#:html-attributes` and `#:head` replace the document-language and head
  string replacements.
- `#:site-nav` and `#:home-link` replace the navigation insertion.
- `#:title-decoration` replaces the regex that decorated tree headings and the
  table of contents with taxa.
- `#:article?` replaces the reading-column `<article>` wrapper.
- `#:backmatter-details?` replaces the regex that made backmatter collapsible.

Standalone subtree pages now list their owning tree in the backmatter Context
section, not only explicit transcluders — verified on
`blazek2005-front-ack.html` (2026-10-10).

Script elements now serialize their children as raw text (grove commit
`f60c61a`, 2026-10-11): previously every emitted script had `&&`, `<`, `>`
HTML-escaped, which threw `SyntaxError` in the browser and killed Grove's own
backmatter runtime on all pages with collapsible backmatter. Flora's MathJax
head configuration no longer needs to avoid those characters.

`make-element` passes its declared `#:flow-kind` through to the content
element (grove commit `384234e`, 2026-10-11): block-flavoured custom tags
(Flora's `figure`/`figcaption`) are no longer wrapped into a `<p>` by the
composition, so Flora can drop the build-the-content-style-itself
workaround.

Childless non-void elements serialize with explicit end tags instead of
`<span …/>` (same commit): the HTML parser no longer keeps an empty custom
element open swallowing the markup that follows, so the empty-string-child
workaround can go. The serializer rewrite also fixed script/style contents
being emitted twice — once raw and once escaped — which made every inline
script run twice.

Page frontmatter topics now have direct accessors (grove commit `e34cd60`,
2026-10-11): `page-taxon`/`page-tags` return a tree's own topic elements, and
`#:title-decoration` receives `(forest page)` instead of `(forest id)` —
Flora's precomputed taxa table and its document scan are gone; the hook body
is now `(lambda (_ page) ...)` over `(page-taxon page)`.

Renamed assets no longer break the next build (grove commit `998f3d6`,
2026-10-11): a stale build-state path (flora.js after the theme.js rename)
used to crash both input-cache pruning and stale-output cleanup with a
missing-file `stat`; vanished paths are pruned silently now. The text
renderer also resolves backlink sources through the page index instead of a
linear scan (`98e1252`).

Flora composes these options in `project.scm`; see Grove's `docs/project.md`
for the contract and `tests/unit/forester/render.scm` for coverage.

## Open

### Margin-note lane: resolved in Flora with lane-items layout (2026-10-11)

The `sidenote` pilot used to float each note into the contents lane at its
anchor's line (float + negative offset), colliding with the sticky table of
contents; Flora layered a paper veil over the overlap and shipped a
scroll-tracking dodge in theme.js.

The experiment settled on lane-items layout. Each note is moved OUT of its
anchor paragraph into the `[notes]` grid lane as a real lane item — theme.js
relocates them once on wide viewports (and back below 60rem, memoizing
anchor spots):

- `.notes-lane` is a body-grid child: `grid-column: notes; grid-row: 2;
  position: sticky; inset-block-start: 1.25rem; max-block-size:
  calc(100svb - 2.5rem); overflow-y: auto; display: flex; flex-direction:
  column; gap: .8lh;`
- `.flora-sidenote` inside the lane is a plain block — no float, no
  negative offsets, no veil. The column keeps notes clear of the contents
  lane by construction; the scroll-tracking dodge, its transition classes,
  the `::after` veil, and the `--notes-w/--notes-gap` rem mirror are all
  deleted.

Verified on `blazek2005-ch11.html` (5 notes): zero note/TOC box
intersections, TOC and lane on opposite sides of the grid. Trade-off
recorded: lane items stack in document order, not at each anchor's line;
the inline counters keep the association with the article text. A sticky
TOC plus anchor-positioned notes cannot be made collision-free in pure CSS
(a stuck element overlaps following siblings by design) — that pair needs
either the JS dodge or this lane-items layout. When Grove absorbs a lane
container/hook, only the relocation JS would go.

### Term definitions as anchors

The `defn` pilot outputs `<dfn>` for glossary defining occurrences. Grove's
anchor registry currently tracks headings, subtrees, and equations; registering
definition elements would let link fragment validation and term queries
("where is this term defined?") see them. The relations DSL could then host a
`term-definition` schema alongside reference facts.

First half done (grove commit `675192b`, 2026-10-11): anchored ordinary
elements are now registry entries. `make-element` grew `#:anchor` — it
renders as the tag's `id` and lands in `page-anchor-facts` — so Flora's defn
becomes `(make-element #:tag "dfn" #:anchor "term-loom")` and fragment
validation covers term anchors. Normalization follows the topic convention:
the anchor id is the canonical key (Flora derives it from the term text,
downcased and hyphenated, with an explicit id overriding). The
`term-definition` relation schema waits for real term queries to say what it
must hold — synonyms, multilingual variants, and per-term multiple
definitions are content-modeling questions that one pilot cannot answer.

### Serve shows a stale artifact snapshot

`grove serve` kept serving the CSS from its startup build while serving
freshly built HTML, so style and markup updates did not arrive together.
The watcher also burns more CPU than a file-watcher should. Restarting serve
(or having serve re-stat artifacts per request) would keep preview iterations
trustworthy; the watcher cost is worth a separate look.

Observed concretely on 2026-10-09: with serve watching, a manual `grove build`
in the same tree formed a rebuild feedback loop — the manual build's writes
triggered serve rebuilds (and presumably vice versa), serve sat at ~40% CPU
for two hours, and the manual build appeared to hang in the analysis phase for
35+ minutes. Killing serve let the same build finish in 2.5 minutes. The
watcher should debounce, ignore writes caused by its own rebuilds, and
ideally take a lock so a serve watch and a manual build cannot build
concurrently.

Controlled reproduction on bb720b4 (2026-10-11, port 8125, initial full
build ~170 s):

- style.css only: the update ARRIVES, but through three chained full
  rebuilds (~5–7 min total). Each cycle's writes re-trigger the watcher
  (the output directory is watched), then the chain settles once a cycle's
  writes stop changing anything. ch02's HTML stayed byte-identical
  throughout — generation isolation holds.
- one `.plant` only: single cycle, 182 s to the served update, no chain.
- style.css + `.plant` together: both arrive in the same generation at
  179 s — the mismatch ("CSS old, HTML new") did not reproduce without
  interference; it matches the churn window of the chained cycles.
- manual `grove build` while serve watch runs (bounded at 150 s): completed
  in place; serve burned ~202 s CPU over the 150 s window digesting the
  manual build's writes; no 35-minute hang at this scale — but the churn
  mechanism (own-writes re-triggering) is exactly what fed the 10-09
  incident.

### Serve workspace cache: per-rebuild generations accumulate and are never reused

`serve.scm` gives every rebuild a fresh generation directory
(`XDG_CACHE_HOME=<workspace>/cache-N`, generation incremented in
`start-build!`), old generations are never pruned while serving, and the
workspace is only removed by the graceful-exit `cleanup!`. Observed on
2026-10-10:

- A serve watching an actively edited project accumulated 52 generations
  (~200 MB each for Flora) — a 12 GB workspace. Nothing was corrupted; disk
  simply grew by one full render cache per rebuild. Hard-killed sessions also
  leave workspaces behind (eleven orphans totalling ~1.9 GB, collected
  manually the same day; SIGTERM does clean the workspace correctly).
- Each generation starts from an empty cache, so every rebuild re-reads and
  re-renders the whole project even when a single `.plant` changed. The
  safety prerequisites for a stable, reused cache directory are already in
  place: input-cache entries are content-fingerprint addressed (identity
  covers the reader, Grove version, locale, load paths, and dependency
  snapshots), entries are written atomically via temp file + rename, and
  workers are strictly serialized (the watch loop only starts a build when
  no worker is running, later changes queue in `pending`).

Suggestion: point the worker at a stable `workspace/cache` and prune the
previous generation in `start-build!` (or cap the generation count), and
optionally sweep orphaned `.grove-preview-*` workspaces older than a threshold
on serve startup. A stable cache would also make the serve/build locking
sketched above easier to reason about.
