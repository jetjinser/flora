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

Flora composes these options in `project.scm`; see Grove's `docs/project.md`
for the contract and `tests/unit/forester/render.scm` for coverage.

## Open

### make-element ignores its #:flow-kind argument

`(grove element)`'s `make-element` destructures `#:flow-kind` but never uses
it — `element-command` hardcodes `#:flow-kind 'inline`. Block-flavoured
custom tags (Flora's `figure`/`figcaption`) therefore render as inline
elements and get wrapped into a `<p>` by the composition, producing
`<p><figure>…</figure></p>`. Flora works around it by building the content
style itself; `make-element` passing `flow-kind` through would remove the
need.

### Page and tree metadata at render time

Flora recomputes each page's own taxon in the render phase by scanning
`content-document-children` for a top-level `taxon` element. A direct accessor
for the current page/tree frontmatter (taxon, tag, summary, published) would
remove that scan.

### Margin-note lane placement

The `sidenote` pilot (defined through `(grove element)`, styled in Flora)
floats each note into the contents lane from inside its anchor paragraph.
Pure CSS handles placement and cascade, but two limits showed up:

- A note anchored near the page top crosses the sticky table of contents.
  Flora layers notes above it as translucent backdrop-blur cards, so both
  stay faintly legible; a renderer-owned margin lane would still place notes
  collision-free instead of layering.
- The lane offset mirrors the grid's first column and gap in `rem`, because
  `ic`-based lengths would rescale at the note's smaller font size. A named,
  renderer-owned margin lane would remove this duplication.

### Term definitions as anchors

The `defn` pilot outputs `<dfn>` for glossary defining occurrences. Grove's
anchor registry currently tracks headings, subtrees, and equations; registering
definition elements would let link fragment validation and term queries
("where is this term defined?") see them. The relations DSL could then host a
`term-definition` schema alongside reference facts.

### Empty elements serialize as self-closing

A custom element with no children renders as `<span …/>`. The HTML parser
ignores the slash on non-void start tags, so the element stays open and
swallows the markup that follows it. Flora works around this by giving the
marker span an empty-string child; the serializer could emit `<! …>`-style
explicit close tags (or void only whitelisted names) instead.

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
