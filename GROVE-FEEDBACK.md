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

Serve now names the changed paths that triggered a rebuild (grove commit
`38cf57e`, 2026-10-11): chained rebuilds — a build's own writes re-triggering
the watcher — print their feedstock on stderr instead of appearing as
unexplained full rebuilds. Grew directly out of the controlled reproduction
below.

Flora composes these options in `project.scm`; see Grove's `docs/project.md`
for the contract and `tests/unit/forester/render.scm` for coverage.

## Open

### Margin-note lane: absorbed upstream as `#:side-lane`, adopted (2026-10-12)

The `sidenote` pilot used to float each note into the contents lane at its
anchor's line (float + negative offset), colliding with the sticky table of
contents; Flora layered a paper veil over the overlap and shipped a
scroll-tracking dodge in theme.js.

The experiment settled on lane-items layout, and Grove absorbed it
(grove commit `4a60360`, 2026-10-12): `#:side-lane` names the content element
kinds the renderer lifts at render time — the anchor paragraph keeps a
numbered `sup.margin-ref` marker, and a page-level `div.margin-lane`
collects the notes in document order, each with a `margin-backref` link.
Flora adopted it and theme.js's relocation JS is gone; CSS places the lane
(the article is a subgrid across the reading and notes lanes, the lane
shares the page-tree's row so sticky travel works), CSS counters renumber
`.margin-item`s to match the renderer's markers, and below 60rem the lane
becomes a bordered endnote group after the tree. Verified on
`blazek2005-ch11.html` (5 notes): zero note/TOC intersections, sticky
confirmed at scroll position 4749, marker/counter sequences agree.

One composition trap worth recording: `#:side-lane` matches
`content-element-kind`, but `make-element` — the public vocabulary API —
always produced `'span`-kinded elements (the tag lives in the style), so a
sidenote built with it rendered as a raw unknown tag, never lifted. Resolved
in grove commit `4597d67` (2026-10-12): `make-element` grew `#:kind` and the
docs point side-lane users at it; Flora's sidenote is back on the public API
(`#:tag "span" #:class "flora-sidenote" #:kind 'flora-sidenote`).

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
downcased and hyphenated, with an explicit id overriding — flora-side this
is `@defn[#:id "…"]`, exercised on `/commands.html`). The
`term-definition` relation schema waits for real term queries to say what it
must hold — synonyms, multilingual variants, and per-term multiple
definitions are content-modeling questions that one pilot cannot answer.

### A `.plant` document has no definition context for `@(...)`

A plain `@(define …)` in a page dies with Guile's "definition in expression
context"; the working idiom is a `@(begin (define …) …)` splice, which
nothing hints at. Flora hit this while writing its first page-local helpers
(`fragment-text`/`term-id` for `defn`) and only stopped needing it by moving
the helpers into library modules. Module files opened with
`@(define-module …)` are unaffected — plain `@(define-public …)` works
there — so the contract differs by file kind with no visible signal. At
minimum the plant-language docs should show the begin-splice idiom; nicer,
Grove could splice bare top-level definitions in a document into the
evaluation environment, so a page-local helper reads like Scheme rather
than like a workaround.

### Command bodies need a public plain-text projection: resolved upstream

Deriving an anchor id from a command body (Flora's `defn` → `term-id`)
needs flattening content fragments to text. Grove had exactly this only in
`(forester private content-index)`, so Flora duplicated it as
`fragment-text` in `lib/commands.plant`. Resolved in grove commit
`d13f423` (2026-10-12): `(grove ir)` exports `content->plain-text` —
strings pass through, text and layout unwrap, elements recurse with
kind-specific joiners, documents concatenate. Flora deleted
`fragment-text` and calls it directly.

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

Grove side, since the reproduction: builds over one project now serialize
on a build lock (grove commit `5a023cb`, 2026-10-12) — a serve watch and a
manual build wait for each other instead of racing, and the wait announces
itself on stderr. Serve also names the changed paths that trigger each
rebuild (`38cf57e`); on a fresh serve the first watch cycle reported 176
"changed" store/module paths — the watch set's own first expansion counted
as edits — which explains one wasted full rebuild per serve start and
should narrow the chain's trigger list on the next reproduction run. That
first-expansion miscount and the per-rebuild generations are both fixed
now (grove commit `69b015b`, 2026-10-12): one stable `workspace/cache`
(grove's double-run experiment rendered 0 affected artifacts on the second
pass), orphaned workspaces swept at startup via a `.live` flock, and the
post-build watch comparison ignores first-sighting additions.

Two more landed alongside: `#:side-lane` lifts margin-note kinds into a
page-level lane container at render time (grove commit `4a60360`) — once
Flora adopts it, theme.js's note relocation can retire; and margin-note
styling has a small default (`.margin-ref`, `.margin-lane`, `.margin-item`).
One caveat filed for the serve tests themselves: under the blue test driver
the spawned serve is a grandchild process where libgcrypt's hash call dies
with ENOSYS, so the serve lifecycle suite cannot run inside `blue check` on
this machine (direct serve runs are unaffected).

Controlled reproduction on d2c5a65 (2026-10-12, port 8125, workspace
`.grove-preview-BQUZmO`, initial full build 85 s from the empty workspace
cache; full log at `/tmp/serve-d2c5a65.log`):

- No phantom rebuild: 75 s of quiet after "Watching for changes" produced
  zero rebuild cycles — the first-sighting miscount is gone.
- style.css only: `Rebuilding (1 changed path):` names exactly
  `/home/jinser/vie/writing/flora/style.css`; ONE cycle (the three-cycle
  chain is gone), 1 affected artifact (flora.css), 144 s to arrival.
- one `.plant` (`blazek2005-r11-5.plant`): `Rebuilding (1 changed path):`
  names the plant; single cycle, 8 affected (the page plus feed/sitemap and
  backlink-bearing pages), 138 s, update visible on the served page.
- manual `grove build` while serve watches: the manual build took the lock
  first and finished in place (141 s, 1952 affected — its own cache was
  cold for d2c5a65), and the serve rebuild queued behind it, printing
  "Waiting for the project build lock; another Grove build is running..."
  on stderr. No hang, no churn.
- workspace: exactly one `cache/` directory beside `.live`,
  `request.scm`, `result.scm`; no `cache-N` generations; SIGTERM removed
  the workspace.

Two residuals observed on the d2c5a65 run, and their status after
`63532f6` (reproduction repeated 2026-10-12, port 8125, initial full build
89 s, no phantom rebuilds; trigger lists — style.css only: 1 path, 1
affected artifact, single cycle; one `.plant`: 1 path, 1 affected; full
log at `/tmp/serve-63532f6.log`):

1. Reverting an input to a previous content left the output stale. FIXED
   for the quiet case: with both probes removed while no build was
   running, serve reported `Rebuilding (2 changed paths):` naming both
   files, re-rendered (9 affected, 106 s), and the served output healed
   immediately — no manual build needed.
2. A manual build over a `build/` directory last written by serve comes
   out `1952 affected` (full invalidation) even with a warm input cache —
   presumably the shared output manifest changing hands. Correctness is
   fine now that the lock serializes them; it is purely wasted work.
   Re-observed on 63532f6 (healing build: 1952 affected, 117 s).

### Mid-build source drift still escapes the drift check

The quiet-revert fix (`63532f6`) re-fingerprints sources after writing the
build state and deletes the state on drift. Reverting a source DURING the
build still poisons the output, deterministically, on 63532f6: append a
line to style.css, let the rebuild start, and revert the file ~25 s in —
after the worker loaded the project but before it finished analyzing. The
cycle reported `1 affected` (writing the probe content), the next cycle —
triggered by the revert — reported `0 affected` and rewrote the stale
artifact. The state file (workspace `cache/grove/<hash>/.grove-build-state`)
held the contradiction in one record: source digest `bff11291` (the clean
post-revert file) beside artifact content `80cc8f1c` (the probe text).

The gap: the drift check compares two fingerprint observations that both
postdate the revert, but the render's content predates them — the worker
reads style.css when it evaluates project.scm (`flora-style` inlines
`call-with-input-file` at load), then fingerprints the same file much
later in execute-project. A change landing between load and fingerprint
poisons the artifacts while every recorded fingerprint stays consistent.
The drift check would need the load-time reads fingerprinted (or the
state to carry the content digests the render actually consumed) to close
this window.

### Serve workspace cache: resolved upstream (grove commit `69b015b`, 2026-10-12)

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

All three landed in grove commit `69b015b` (2026-10-12) and verified on
d2c5a65 (see the d2c5a65 reproduction above): one stable `workspace/cache`
across rebuilds, orphan sweep at startup behind a `.live` flock, graceful
exit removes the workspace. Nothing further open here beyond the two
residuals recorded above.

### No project discovery: running from a subdirectory fails with a bare stat error

Commands resolve their project file as `./project.scm` relative to the
invocation directory, with no upward search, so any command run inside the
project tree fails at load. Reproduced on `38cf57e`, running `grove check`
from `flora/plants/lib`:

    Checking project.scm
    grove: load failed (project.scm)
    In procedure canonicalize-path: No such file or directory

Half-resolved in grove commit `465fa08` (2026-10-12): the load now checks
existence first and reports "no project file at <path>; pass --project or
run from the project root" instead of the bare stat error. Upward
discovery (git-style) remains open as a separate question.
