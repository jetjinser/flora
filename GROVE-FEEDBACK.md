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

Three concrete queries from Flora's translation corpus to size that schema
(2026-10-13):

1. Defined-term index. `/glossary` is hand-maintained `@item{@defn{tree}
   （树）：…}` entries that duplicate what `defn` occurrences already know
   and drift from them. A `term-definitions` query — term-id → list of
   (page, anchor, display text) — would generate the glossary listing (and
   the hover-preview text for term markers) from the corpus instead.

2. Conflicting definitions. A chapter's in-passing `@defn` can diverge
   from the glossary's canonical entry over edits; nothing notices.
   Counting defining pages per term-id (and comparing display texts when
   the count is > 1) is a consistency query over the same relation — the
   multilingual angle rides along: the same term-id often has an English
   original and a Chinese defining text on the same page, so display text
   belongs in the relation, not just the id.

3. Undefined mentions. Chapters use terms that no page defines; today
   that is discoverable only by reading. A mentions-side fact (term-id →
   pages that use it, from unresolved fragment links to term anchors, or
   from `@term` occurrences if mentions get marked) turns "which terms
   still need a definition" into a query — actionable backlog for the
   translation.

Schema implication: the definition relation needs (term-id, page, anchor,
display text) at minimum; query 3 additionally wants a mentions relation.
Everything keys on the normalized term-id; nothing above needs synonyms as
first-class data yet.

Implemented in grove commit `dd0a5dd` (2026-10-13), following this schema.
Facts come from anchored elements tagged `dfn` — the HTML defining-instance
semantic, so Flora's existing `(make-element #:tag "dfn" #:anchor …)` needs
no change — with the display text taken from the element's plain-text body
(an original term and a translation ride in one element, per query 2).
Mentions are fragment links (`link`/`query-link`) whose fragment does not
resolve in the target page's anchor index — the same condition the fragment
warning reports, collected as data; an explicit `@term` marking convention
can replace that source later if Flora wants mentions of defined terms
too.  Forest-level queries, all exported from `(forester site)`:

- `(term-definitions forest "term-loom")` → `(page-id anchor display-text)`
  rows for query 1 (glossary listing, hover previews).
- `(term-definition-conflicts forest)` → `(term-id (page-id display-text)
  …)` for every term defined on more than one page or with differing
  display texts — query 2.
- `(undefined-term-mentions forest)` → `(term-id (page-id …))` grouped and
  sorted — query 3, the definition backlog.

The relation constructors and `term-definitiono`/`term-mentiono` goals are
exported from `(forester relations)` for queries beyond these three.
Documented in docs/forester-composition.md ("Term definitions").

Adopted in Flora same-day (2026-10-13), with the trial this schema was
sized for:

- `/glossary`'s first group is defn-backed — each entry wraps its term and
  gloss in `@defn[#:id "…"]`, so the relation's display text is the
  compact label ("tree（树）") while the description stays item prose.
  Sixteen terms registered; the other five groups are still hand-written
  and invisible to the relation — exactly the hand-maintenance drift the
  schema exists to catch, now visible as absence.
- `/queries` gained two marker commands filled at analyze time:
  `@term-index` (the generated defined-term list, collection order, with
  a link when the definition lives on another page) and `@term-conflicts`
  (drift report plus backlog). The literal "replace the hand-maintained
  list" step waits on the corpus: with only one group registered, a
  generated glossary would be near-empty — groups convert as their
  entries become defn-backed.
- Conflicts output verified against the drift intuition with a planted
  in-passing definition (`@defn[#:id "tree"]` with a different gloss on a
  tutorial page, reverted after): the report read
  `tree：tree（树）（glossary-grove）  tree（树），本页口径（unstable-8）`
  — canonical entry first (collection order), drifted occurrence with its
  page after. One reading note: the defining page for an in-paragraph
  defn is the owning subtree's own page id (`unstable-8`), not the
  article's — correct, but surprising at first glance.
- Backlog was empty on the real corpus: Flora has no fragment links aimed
  at missing anchors yet.

For the `@term` convention (mentions of defined terms): emit a link
element with properties `((target . <defining page>) (fragment . <anchor>)
(term . "term-id"))`, resolved at analyze time against the definition
relation — display text from the canonical entry, undefined targets
surfacing in the backlog report instead of rendering as dead links. Two
design points from the trial: the marker should key on the RAW anchor
registry, not rendered DOM ids (rendered anchors carry subtree prefixes —
`glossary-grove--tree` — so a raw `#tree` fragment counts as unresolved
even when the term exists); and explicit marking keeps term mentions
distinguishable from ordinary links, so the mention relation can count
resolved and unresolved mentions without guessing.

### A `.plant` document has no definition context for `@(...)`: resolved upstream (grove commit `79b9688`, 2026-10-12)

A plain `@(define …)` in a page dies with Guile's "definition in expression
context"; the working idiom is a `@(begin (define …) …)` splice, which
nothing hints at. Flora hit this while writing its first page-local helpers
(`fragment-text`/`term-id` for `defn`) and only stopped needing it by moving
the helpers into library modules. Module files opened with
`@(define-module …)` are unaffected — plain `@(define-public …)` works
there — so the contract differs by file kind with no visible signal.

Re-checked against the current reader (2026-10-12): the reported failure no
longer reproduces. Each top-level `@(...)` form evaluates in the page
environment, so a bare `@(define (helper) …)` anywhere at the top level of a
`.plant` page — including between paragraphs — binds `helper` for every later
form; the begin-splice workaround is obsolete. A definition inside a command
argument is still rejected with "definition in expression context", which is
Scheme's own rule. Grove pinned both sides with scribble read tests and
stated the contract in docs/project.md ("Executable source and module
articles"). The `term-definition` note below stands as the only follow-up.

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
   RESOLVED upstream (grove commit `02f0362`, 2026-10-12): the serve
   worker stopped keeping a private cache under the preview workspace and
   now inherits the serve process's environment, so serve and manual
   builds share the per-project cache directory — build state, artifact
   manifest, and input cache — with the build lock serializing writers.
   Sharing surfaced a second gap: project loads record load-path
   candidates (module sources and compiled-object paths, often for files
   that do not exist) into extra-sources, and those candidate sets shift
   between build processes. The build state now tags source entries as
   declared or runtime; absent entries are ignored on both sides of the
   comparison and a removed-and-re-added runtime pair with equal content
   cancels, since neither can change what a build produces. Grove's serve
   lifecycle suite pins the contract — a manual build after a serve
   session reports 0 affected — and also covers editing while serve
   watches. Flora-side verification welcome on a real tree: manual build
   over a serve-written `build/` should now stay incremental.
   VERIFIED on the flora tree (2026-10-13, grove `5f5606d`): the serve
   workspace now holds only `.live`/`request.scm`/`result.scm` — no
   `cache/`; build state and input cache live at
   `~/.cache/grove/d111fa1384d6b861/` for both processes. Serve's initial
   build over a manual build's output reported `0 affected` (94 s, pure
   analysis), and a manual `grove build` after a serve session — the
   direction that used to full-invalidate — reported `0 affected` in
   114 s ("Cached Renderer cache hit").

### Mid-build source drift: resolved upstream (grove commit `fda4c0a`, 2026-10-12)

The quiet-revert fix (`63532f6`) re-fingerprints sources after writing the
build state and deletes the state on drift. Reverting a source DURING the
build still poisoned the output, deterministically, on 63532f6: append a
line to style.css, let the rebuild start, and revert the file ~25 s in —
after the worker loaded the project but before it finished analyzing. The
cycle reported `1 affected` (writing the probe content), the next cycle —
triggered by the revert — reported `0 affected` and rewrote the stale
artifact. The state file (workspace `cache/grove/<hash>/.grove-build-state`)
held the contradiction in one record: source digest `bff11291` (the clean
post-revert file) beside artifact content `80cc8f1c` (the probe text).

The gap: the drift check compared two fingerprint observations that both
postdate the revert, but the render's content predates them — the worker
reads style.css when it evaluates project.scm (`flora-style` inlines
`call-with-input-file` at load), then fingerprints the same file much
later in execute-project.

Fixed in grove commit `fda4c0a`: extra-sources fingerprints are captured
as a pre-build snapshot before the analysis runs — the load-time baseline
the render actually consumed — and the end-of-build check compares against
both snapshots. Verified on the same steps (2026-10-13, grove `5f5606d`,
port 8125): the probe cycle reported `1 affected`, and the revert cycle
came back `1952 affected` in 85 s — the state had been deleted, forcing
the full re-render — leaving the output clean with no manual build. The
one full re-render is the correct price for an ambiguous build.

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

### No project discovery: running from a subdirectory fails with a bare stat error: resolved upstream (grove commit `5f5606d`, 2026-10-12)

Commands resolve their project file as `./project.scm` relative to the
invocation directory, with no upward search, so any command run inside the
project tree fails at load. Reproduced on `38cf57e`, running `grove check`
from `flora/plants/lib`:

    Checking project.scm
    grove: load failed (project.scm)
    In procedure canonicalize-path: No such file or directory

Half-resolved in grove commit `465fa08` (2026-10-12): the load now checks
existence first and reports "no project file at <path>; pass --project or
run from the project root" instead of the bare stat error.

Resolved in grove commit `5f5606d` (2026-10-12): without `--project`,
commands search the invocation directory and its ancestors git-style and
stop at a `.git` boundary or the filesystem root; an explicit `--project`
always wins. The CLI suite pins discovery from a subdirectory, the boundary
stop, and the escape hatch. For Flora this means `grove check` from
`flora/plants/lib` now finds `flora/project.scm` and runs.
