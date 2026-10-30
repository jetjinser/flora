# SPDX-FileCopyrightText: 2026 Jinser Kafka <aimer@purejs.icu>
#
# SPDX-License-Identifier: GPL-3.0-or-later

GROVE ?= grove
GROVE_ROOT ?= ../grove
REUSE ?= reuse

.PHONY: help validate test check build serve lint a11y preview-check \
	update-doi-metadata update-zenodo-metadata update-crossref-metadata clean

help:
	@printf '%s\n' \
	  'make validate    Validate the project' \
	  'make test        Run offline project tests' \
	  'make build       Build the site' \
	  'make update-doi-metadata DOI=doi:10.../...  Refresh one local metadata snapshot' \
	  'make update-crossref-metadata DOI=doi:10.../...  Refresh via Crossref REST API' \
	  'make update-zenodo-metadata URI=https://zenodo.org/records/ID  Refresh a Zenodo dataset snapshot' \
	  'make serve       Preview the site' \
	  'make lint        Check REUSE license compliance' \
	  'make a11y        Build and run the browser accessibility audit' \
	  'make preview-check  Check link-preview keyboard behavior' \
	  'make check       Full gate: validate + test + lint + a11y + preview-check' \
	  'make clean       Remove build output'

validate:
	$(GROVE) check

test:
	guile --no-auto-compile -L . tests/lp-core.scm
	guile --no-auto-compile -L . tests/lp-project.scm
	guile --no-auto-compile -L "$(GROVE_ROOT)/modules" -L . tests/figure-page-cache.scm
	guile --no-auto-compile -L "$(GROVE_ROOT)/modules" -L . tests/entity-snapshot.scm
	guile --no-auto-compile -L "$(GROVE_ROOT)/modules" -L . tests/doi-metadata.scm
	guile --no-auto-compile -L "$(GROVE_ROOT)/modules" -L . tests/zenodo-metadata.scm
	guile --no-auto-compile -L "$(GROVE_ROOT)/modules" -L . tests/crossref-metadata.scm
	guile --no-auto-compile -L . tests/entity-metadata.scm

build:
	$(GROVE) build

serve:
	$(GROVE) serve

update-doi-metadata:
	@test -n "$(DOI)" || { echo 'usage: make update-doi-metadata DOI=doi:10.../...' >&2; exit 2; }
	guile --no-auto-compile -L "$(GROVE_ROOT)/modules" -L . \
	  scripts/update-doi-metadata.scm "$(DOI)"

update-zenodo-metadata:
	@test -n "$(URI)" || { echo 'usage: make update-zenodo-metadata URI=https://zenodo.org/records/ID' >&2; exit 2; }
	guile --no-auto-compile -L "$(GROVE_ROOT)/modules" -L . \
	  scripts/update-zenodo-metadata.scm "$(URI)"

update-crossref-metadata:
	@test -n "$(DOI)" || { echo 'usage: make update-crossref-metadata DOI=doi:10.../...' >&2; exit 2; }
	guile --no-auto-compile -L "$(GROVE_ROOT)/modules" -L . \
	  scripts/update-crossref-metadata.scm "$(DOI)"

lint:
	$(REUSE) --no-multiprocessing lint

a11y: build
	@test -x "$(GROVE_ROOT)/scripts/a11y-audit.sh" || { \
	  echo "a11y: set GROVE_ROOT to a Grove checkout with scripts/a11y-audit.sh" >&2; \
	  exit 1; \
	}
	"$(GROVE_ROOT)/scripts/a11y-audit.sh" \
	  build/index.html \
	  build/math-0003.html \
	  build/lp-0001.html \
	  build/blazek2005-ch02.html

check: validate test lint a11y preview-check

clean:
	rm -rf build

preview-check: build
	scripts/preview-check.sh
