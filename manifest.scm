;;; SPDX-FileCopyrightText: 2026 Jinser Kafka <aimer@purejs.icu>
;;;
;;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Grove and Flora development tools.

(use-modules (gnu packages)
             (grove packages))

(packages->manifest
 (cons* grove
        (list (specification->package "libavif") "tools")
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
