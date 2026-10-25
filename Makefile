# SPDX-FileCopyrightText: 2026 Jinser Kafka <aimer@purejs.icu>
#
# SPDX-License-Identifier: GPL-3.0-or-later

GROVE ?= grove
GROVE_ROOT ?= ../grove
REUSE ?= reuse

.PHONY: help validate check build serve lint a11y preview-check update-doi-metadata clean

help:
	@printf '%s\n' \
	  'make validate    Validate the project' \
	  'make build       Build the site' \
	  'make update-doi-metadata DOI=doi:10.../...  Refresh one local metadata snapshot' \
	  'make serve       Preview the site' \
	  'make lint        Check REUSE license compliance' \
	  'make a11y        Build and run the browser accessibility audit' \
	  'make preview-check  Check link-preview keyboard behavior' \
	  'make check       Full gate: validate + lint + a11y + preview-check' \
	  'make clean       Remove build output'

validate:
	$(GROVE) check

build:
	$(GROVE) build

serve:
	$(GROVE) serve

update-doi-metadata:
	@test -n "$(DOI)" || { echo 'usage: make update-doi-metadata DOI=doi:10.../...' >&2; exit 2; }
	guile --no-auto-compile -L "$(GROVE_ROOT)/modules" -L . \
	  scripts/update-doi-metadata.scm "$(DOI)"

lint:
	$(REUSE) --no-multiprocessing lint

a11y: build
	@test -x "$(GROVE_ROOT)/scripts/a11y-audit.sh" || { \
	  echo "a11y: set GROVE_ROOT to a Grove checkout with scripts/a11y-audit.sh" >&2; \
	  exit 1; \
	}
	"$(GROVE_ROOT)/scripts/a11y-audit.sh" \
	  build/index.html build/blazek2005-ch02.html

check: validate lint a11y preview-check

clean:
	rm -rf build

preview-check: build
	scripts/preview-check.sh
