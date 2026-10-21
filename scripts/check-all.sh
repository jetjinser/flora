#!/bin/sh
# SPDX-FileCopyrightText: 2026 Jinser Kafka <aimer@purejs.icu>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Full Flora check: project validation, license audit, build, and axe.
# Run inside Grove's development shell.  GROVE_ROOT selects the Grove
# checkout that provides @use-commands (default: ../grove).

set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
grove_root=${GROVE_ROOT:-$root/../grove}
grove_root=$(CDPATH= cd -- "$grove_root" && pwd)

if [ ! -f "$grove_root/scripts/a11y-audit.sh" ]; then
    echo "check-all: Grove checkout not found at $grove_root" >&2
    echo "set GROVE_ROOT to the Grove checkout" >&2
    exit 1
fi

cd "$root"

guile --no-auto-compile \
    -L "$grove_root/modules" -C "$grove_root/build" -L "$grove_root" \
    -c '(use-modules (grove cli)) (exit (main (list "check" "--project" "project.scm")))'

reuse --no-multiprocessing lint

guile --no-auto-compile \
    -L "$grove_root/modules" -C "$grove_root/build" -L "$grove_root" \
    -c '(use-modules (grove cli)) (exit (main (list "build" "--project" "project.scm")))'

exec "$grove_root/scripts/a11y-audit.sh" \
    "$root/build/index.html" \
    "$root/build/blazek2005-ch02.html"
