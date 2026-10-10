# Flora

Flora is an executable tutorial site built with Grove. Its `.plant` files combine prose, document commands, and Scheme expressions. Grove analyzes the resulting content trees, evaluates build-time computations, and renders the site.

## Build and preview

From the Flora directory, enter the Grove development environment:

```sh
nix develop ../../projet/prototype/grove/nix
```

If you need to install the CLI, change to the Grove checkout and install it to a temporary prefix:

```sh
cd ../../projet/prototype/grove
blue prefix=/tmp/grove-install exec-prefix=/tmp/grove-install \
  bindir=/tmp/grove-install/bin \
  guile-module-dir=/tmp/grove-install/share/guile/site/3.0 \
  guile-object-dir=/tmp/grove-install/lib/guile/3.0/site-ccache \
  build -- install
export PATH=/tmp/grove-install/bin:$PATH
cd -
```

Return to the Flora directory and run:

```sh
grove check
grove build
grove serve
```

The preview is available at `http://127.0.0.1:8080/`. Use `--port` or `--output` to select another port or output directory. Stop the server with Ctrl-C.

## Book translations

Two book-length translations live in `plants/`, both as paragraph-level bilingual pages: the English source is folded under each Chinese paragraph, formulas are re-typeset as LaTeX with per-equation anchors, citations link to per-entry reference trees, and figures are cropped from the scanned source pages.

- **The Elements of Style** (Strunk & White, 4th ed.) — book home `strunk1999` plus nine pages; completed 2026-10-08.
- **Computational Fluid Dynamics** (Blazek, 2nd ed., 2005) — book home `blazek2005` plus fourteen content pages (front matter, chapters 1–12 with appendix A, index) and 1067 reference entries; completed 2026-10-10.

The conventions these follow (bilingual markup, math anchors, citations, figures, subagent workflow) are documented in `docs/translation-guide.md`; per-book records live in `docs/blazek2005-notes.md` and `docs/blazek2005-figures.md`. Source text extractions and the scanned book files are kept under `materials/` (book PDFs in `materials/books/`). A third book (Kazmer, *Injection Mold Design Engineering*) is prepared but not started — see `docs/kazmer2016.md`.

## Fonts

The site pairs Inria (Latin, digits, symbols) with Noto CJK SC (Chinese): serif for prose, sans for navigation, matching the families `style.css` already lists. `cjk-fonts.scm` is a build renderer that collects the site's text universe with `(forester site) used-codepoints`, adds an ASCII and punctuation safety margin, and cuts the source fonts in `fonts-src/` down to woff2 files that cover exactly that universe, so the ~90 MB CJK sources ship as a few hundred kilobytes per weight. Results are cached across builds in the Grove cache directory.

`fonts-src/` is not checked in. Fetch the sources with `./fetch-fonts.sh`, and have `pyftsubset` on `PATH` when building (Guix: `guix shell python-fonttools python-brotli`). Without them the build still succeeds — `fonts/cjk.css` is emitted empty and the system-font stacks in `style.css` take over. Noto CJK is licensed under the SIL Open Font License 1.1; the license files ship in `fonts/`.

## Reading and source layout

The home tree links to four topic indexes:

- `grove.plant` introduces `.plant` documents, trees, and transclusion.
- `math.plant` maps the Formula, Semantic, and Notation experiments.
- `lp.plant` maps the literate-programming library and its examples.
- `strunk1999.plant` maps the Chinese translation of *The Elements of Style*, 4th edition.

A glossary page (`glossary.plant`) collects the terms shared across these topics.

The numbered source files beneath each prefix are stable page identities, not a required reading order: `grove-NNNN`, `math-NNNN`, and `lp-NNNN`. Their four-character suffixes follow Grove's base-36 address convention. A file's name is its page address. Named subtrees use short, descriptive ASCII IDs only when they need a durable link or transclusion; other subtrees use Grove's generated addresses.

`project.scm` declares the source modules, site routes, renderer adapter, and output assets. The sitemap and RSS renderers write `sitemap.xml` and `feed.xml` into the site output alongside the HTML pages, using `https://flora.purejs.icu` as the site URL. HTML pages advertise `feed.xml` for feed-reader autodiscovery; the RSS XML links `feed.css` for browser display. `plants/` contains pages, `plants/lib/` contains the site command library as self-documenting pages, `lp/` contains the experimental literate-programming library, and `tests/` contains its Guile checks. Generated HTML and programs are written to `build/`.

## Writing conventions

Write Chinese prose without manual spaces between CJK text and Latin words or digits. `style.css` uses `text-autospace` for visual separation. Keep spaces required inside English phrases, code, and Scheme source. See [Grove writing](plants/grove-0001.plant).

Margin notes and term definitions are content commands: `@sidenote{…}` attaches a note to the sentence it appears in — it floats into the contents lane on wide screens and folds into the paragraph on narrow ones — and `@defn{…}` marks a term's defining occurrence, rendered as `<dfn>`. When a note crosses the sticky contents, a small script slides the contents up until the note has passed, then lets it settle back; without JS, a paper veil on the note erases the entries beneath it instead. Keep the first note low anyway so it does not cover the contents list.

Each page should make sense when opened or linked on its own. Describe topic relationships through links and indexes; avoid relying on “first”, “next”, or similar wording that loses meaning when a subtree is reused elsewhere.

## Checks

Run the LP library checks and validate the whole site after changing program examples:

```sh
guile --no-auto-compile -L . tests/lp-core.scm
guile --no-auto-compile -L . tests/lp-project.scm
grove check
grove build
```

The metacircular interpreter also emits standalone Guile programs under `build/programs/`. Its finite examples exercise the advertised subset; they are not a proof of equivalence with full Scheme.

## Grove feedback

`GROVE-FEEDBACK.md` collects candidate changes to Grove found while writing these docs; it is not a Flora build input.
