;;; SPDX-FileCopyrightText: 2026 Jinser Kafka <aimer@purejs.icu>
;;;
;;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Flora's own development tools, on top of the Grove toolchain.
;;; Combine with the sibling Grove checkout's manifest and package entry point:
;;;
;;;   guix time-machine -C channels.scm -- shell \
;;;     -m ../grove/manifest.scm -m manifest.scm -f ../grove/guix.scm
;;;   make check
;;;   make build
;;;
;;; Set GROVE_ROOT for Makefile checks if Grove lives elsewhere.

(use-modules (gnu packages))

(packages->manifest
 (cons (list (specification->package "libavif") "tools")
       (map specification->package
            (list "poppler"           ; pdftoppm: rasterize the scanned PDF
                  "imagemagick"       ; magick: crop figures from the pages
                  "libjxl"            ; cjxl: JPEG XL encoding
                  "libwebp"           ; cwebp: WebP encoding
                  "python-fonttools"  ; pyftsubset: cut the CJK woff2 subset
                  "python-brotli"     ; woff2 compression for the subset
                  "make"              ; Makefile entry points
                  "curl"              ; fetch-fonts.sh and axe-core bootstrap
                  "ungoogled-chromium")))) ; browser audits in make check
