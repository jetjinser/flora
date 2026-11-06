# Flora

Flora is an executable tutorial site built with Grove. Its `.plant` files combine prose, document commands, and Scheme expressions. Grove analyzes the resulting content trees, evaluates build-time computations, and renders the site.

## Build and preview

From the Flora directory, enter the Nix development environment; the flake
pins Grove from its upstream repository:

```sh
nix develop
```

Alternatively with Guix, which gets Grove from the pinned Grove channel (no
local Grove checkout is needed):

```sh
guix time-machine -C channels.scm -- shell -m manifest.scm -m smathml/manifest.scm
```

Then use the Makefile from the Flora directory:

```sh
make validate
make build
make serve
make preview
```

`make serve` uses Grove’s preview server. `make preview` serves the existing
`build/` directory with Guile’s built-in HTTP server and does not check,
build, watch, or update the site; run `make build` first. It listens on
`127.0.0.1:8080` by default; set `HOST` or `PORT` to change the address.

`make check` is the full gate: source verification, `validate`, `test`, `lint`,
`a11y`, and `preview-check`. `make a11y` builds and runs the browser audit on
representative home, math, literate-programming, and translated-book pages;
it does not scan every generated page. `make preview-check`
checks the link preview’s focus, Escape, and focusout behavior; `make lint`
checks REUSE compliance. The Makefile uses `grove` from `PATH`; override
`GROVE` to point at another build. The accessibility audit lives in
`scripts/a11y-audit.sh`. Set `CHROMIUM` if the browser is not on
`PATH`. The Guix manifest provides Chromium; the first
accessibility audit downloads a pinned, checksum-verified axe-core bundle and
needs network access unless that bundle is already cached.

The preview is available at `http://127.0.0.1:8080/`. Set `HOST` or `PORT` when invoking `make preview` to choose another address; the served directory is always `build/`. Stop the server with Ctrl-C.

`make verify-sources` checks the SHA-256 digests of the non-Git inputs used by
the complete site: the four Noto CJK source fonts, the Inria webfonts and CSS,
and the Blazek scan PDF. The expected bytes are recorded in
`sources/fonts.sha256` and `sources/materials.sha256`. The PDF remains in a
private archive and is not fetched or redistributed by this project. The font
hashes detect upstream changes after `fetch-fonts.sh`; they do not guarantee
that an upstream URL will continue serving the locked bytes. Grove's store
caches derived figures and build outputs, but is not an archive of these
source files. Builds without CJK sources still support a system-font fallback;
that intentionally produces a different site from the complete-font build.

## External entity metadata

Reference pages declare identifiers with `@describes`. To experiment with
supplemental metadata, explicitly refresh a local snapshot from a source that
provides a machine-readable record:

```sh
make update-doi-metadata DOI=doi:10.1146/annurev.fluid.29.1.123
make update-crossref-metadata DOI=doi:10.1146/annurev.fluid.29.1.123
make update-zenodo-metadata URI=https://zenodo.org/records/11198731
```

Each command stores normalized fields and fetch provenance under
`metadata/entities/`. DOI content negotiation and Crossref's REST API are two
adapters for citations; the Zenodo command accepts a Zenodo HTTPS landing-page
URI and reads its public record API for dataset metadata. Snapshots are
indexed by their declared URI, regardless of scheme. Ordinary `grove build`
reads only these local snapshots and does not access the network. An unchanged
metadata response leaves its snapshot untouched, so it does not trigger an
unnecessary Grove rebuild. All three adapters share the same snapshot writer;
source-specific response validation and field mapping stay in each adapter.
DOI names may contain Unicode in these `doi:` IRIs; the refresh commands
percent-encode them as UTF-8 only for the HTTP request and keep the authored
IRI as the snapshot key. Percent-encode characters that have IRI syntax, such
as `?`, `#`, `<`, or `>`, when they are part of the DOI name; for example, use
`%3F`, `%23`, `%3C`, or `%3E`. The updater compares those escapes with the
literal DOI name returned by the metadata service.
`captured-at` marks when the stored metadata was captured or last changed.
Failed requests and invalid or mismatched records produce a concise error and
leave the previous snapshot intact. The reference page title and text remain
author-controlled; fetched metadata appears as a separate supplement. These
source adapters are an experiment in Flora, not a Grove fetching API.

## Book translations

Two book-length translations live in `plants/`, both as paragraph-level bilingual pages: the English source is folded under each Chinese paragraph, formulas are re-typeset as LaTeX with per-equation anchors, citations link to per-entry reference trees, and figures are cropped from the scanned source pages.

- **The Elements of Style** (Strunk & White, 4th ed.) — book home `strunk1999` plus nine pages; completed 2026-10-08.
- **Computational Fluid Dynamics** (Blazek, 2nd ed., 2005) — book home `blazek2005` plus fourteen content pages (front matter, chapters 1–12 with appendix A, index) and 1067 reference entries; completed 2026-10-10.

The conventions these follow (bilingual markup, math anchors, citations, figures, subagent workflow) are documented in `docs/translation-guide.md`; per-book records live in `docs/blazek2005-notes.md` and `docs/blazek2005-figures.md`. Source text extractions and the scanned book files are kept under `materials/` (book PDFs in `materials/books/`). The scanned books are copyrighted and too large for git, so `materials/` is not tracked: provision it out-of-band (copy the private archive into the checkout) before the first build or after changing figure inputs, because the figure pipeline needs the PDF to produce its outputs. A third book (Kazmer, *Injection Mold Design Engineering*) is prepared but not started — see `docs/kazmer2016.md`.

The 127 blazek2005 figures are not checked in either: `docs/blazek2005-figures.tsv` records each figure's PDF page and crop box, and the `blazek2005-figures` pipeline graph declared in `project.scm` rasterizes each distinct PDF page once, then fans it out to the per-figure crop-and-encode steps during `grove build` (needs `pdftoppm`, ImageMagick, and `avifenc` on `PATH`; the Guix manifest provides them). A small manifest stage emits one private record per figure; changing one crop record invalidates only that figure consumer. Unchanged page bytes likewise preserve figure-stage cache entries even if a page producer reruns. The shared Grove store deduplicates output bytes across checkouts, although stages may rerun because declared file paths are part of their cache identity.

## Fonts

The site pairs Inria (Latin, digits, symbols) with Noto CJK SC (Chinese): serif for prose, sans for navigation, matching the families `style.css` already lists. `cjk-fonts.scm` is a build renderer that collects the site's text universe with `(forester site) used-codepoints`, adds an ASCII and punctuation safety margin, and cuts the source fonts in `fonts-src/` down to woff2 files that cover exactly that universe, so the ~90 MB CJK sources ship as a few hundred kilobytes per weight. Results are cached across builds in the Grove cache directory.

Neither the CJK sources in `fonts-src/` nor the webfonts under `fonts/` are checked in. `./fetch-fonts.sh` fetches both: the Noto CJK sources from the noto-cjk repository, and the Inria webfonts plus `fonts/inria.css` from the Google Fonts css2 API. For CJK subsetting, have `pyftsubset` on `PATH` when building (Guix: `guix shell python-fonttools python-brotli`). Without the CJK sources the build still succeeds — `fonts/cjk.css` is emitted empty and the system-font stacks in `style.css` take over. Noto CJK, Inria Sans, and Inria Serif are all licensed under the SIL Open Font License 1.1; the license files are checked in under `fonts/`.

## Reading and source layout

The home tree links to five topic indexes and one rendering experiment:

- `grove.plant` introduces `.plant` documents, trees, and transclusion.
- `math.plant` maps the Formula, Semantic, and Notation experiments.
- `lp.plant` maps the literate-programming library and its examples.
- `strunk1999.plant` maps the Chinese translation of *The Elements of Style*, 4th edition.
- `blazek2005.plant` maps the Chinese translation of *Computational Fluid Dynamics*, 2nd edition.
- `smathml.plant` presents the SMathML-generated Everything page and its child articles as a renderer integration experiment.

A glossary page (`glossary.plant`) collects the terms shared across these topics.

The numbered source files beneath each prefix are stable page identities, not a required reading order: `grove-NNNN`, `math-NNNN`, and `lp-NNNN`. Their four-character suffixes follow Grove's base-36 address convention. A file's name is its page address. Named subtrees use short, descriptive ASCII IDs only when they need a durable link or transclusion; other subtrees use Grove's generated addresses.

`project.scm` declares the source modules, site routes, renderer adapter, and output assets. The sitemap and RSS renderers write `sitemap.xml` and `feed.xml` into the site output alongside the HTML pages, using `https://flora.purejs.icu` as the site URL. HTML pages advertise `feed.xml` for feed-reader autodiscovery; the RSS XML links `feed.css` for browser display. `plants/` contains pages; the 1067 Blazek reference trees are grouped under `plants/blazek2005/references/` by source chapter while their basenames, IDs, and routes stay unchanged. `plants/lib/` contains the site command library as self-documenting pages, `lp/` contains the experimental literate-programming library, and `tests/` contains its Guile checks. Generated HTML and programs are written to `build/`.

Flora's reader preloads `(forester commands)` and `(flora commands)` for ordinary pages, so Flora-authored `.plant` files do not need a repeated `@use-commands{flora}` header. The command manifest is in `flora.scm`; projects that use Flora's commands can import that set with `@use-commands{flora}`.

## Writing conventions

Write Chinese prose without manual spaces between CJK text and Latin words or digits. `style.css` uses `text-autospace` for visual separation. Keep spaces required inside English phrases, code, and Scheme source. See [Grove writing](plants/grove-0001.plant).

Margin notes and term definitions are content commands: `@sidenote{…}` attaches a note to its sentence; on wide screens it appears in the page's side lane, and on narrow screens it follows the article. `@defn{…}` marks a term's defining occurrence and renders as `<dfn>`.

Each page should make sense when opened or linked on its own. Describe topic relationships through links and indexes; avoid relying on “first”, “next”, or similar wording that loses meaning when a subtree is reused elsewhere.

## Checks

Run the offline tests and validate the whole site after changing program
examples:

```sh
make test
make validate
make build
```

The metacircular interpreter also emits standalone Guile programs under `build/programs/`. Its finite examples exercise the advertised subset; they are not a proof of equivalence with full Scheme.

## Grove feedback

`GROVE-FEEDBACK.md` collects candidate changes to Grove found while writing these docs; it is not a Flora build input.
