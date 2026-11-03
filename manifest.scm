;;; SPDX-FileCopyrightText: 2026 Jinser Kafka <aimer@purejs.icu>
;;;
;;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Grove and Flora development tools.

(use-modules (gnu packages)
             (grove packages)
             (guix build-system gnu)
             (guix download)
             (guix gexp)
             (guix search-paths)
             ((guix licenses) #:prefix license:)
             (guix packages))

;; Temml is a static JavaScript library with no runtime dependencies.  Package
;; its published npm archive directly so the build uses a pinned, Guix-managed
;; source rather than fetching npm dependencies during `make build`.
(define temml
  (package
    (name "temml")
    (version "0.13.5")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "https://registry.npmjs.org/temml/-/temml-"
                           version ".tgz"))
       (sha256
        (base32 "10p5i9prhay2sn0y44kmg2ks3w7hig6gc5yqz20nq7bds9nvg9dw"))))
    (build-system gnu-build-system)
    (arguments
     (list
      #:tests? #f
      #:phases
      #~(modify-phases %standard-phases
          (delete 'configure)
          (delete 'build)
          (delete 'check)
          (replace 'install
            (lambda* (#:key outputs #:allow-other-keys)
              (let ((target (string-append (assoc-ref outputs "out")
                                           "/share/node_modules/temml")))
                (mkdir-p target)
                (copy-recursively "." target)))))))
    (native-search-paths
     (list (search-path-specification
            (variable "NODE_PATH")
            (files '("share/node_modules")))
           (search-path-specification
            (variable "TEMML_PACKAGE")
            (files '("share/node_modules/temml")))))
    (home-page "https://temml.org/")
    (synopsis "TeX to MathML converter")
    (description
     "Temml converts TeX mathematics to MathML for Flora's static HTML build.")
    (license license:expat)))

(packages->manifest
 (cons* grove temml
        (list (specification->package "libavif") "tools")
        (map specification->package
            (list "poppler"           ; pdftoppm: rasterize the scanned PDF
                  "imagemagick"       ; magick: crop figures from the pages
                  "libjxl"            ; cjxl: JPEG XL encoding
                  "libwebp"           ; cwebp: WebP encoding
                  "python-fonttools"  ; pyftsubset: cut the CJK woff2 subset
                  "python-brotli"     ; woff2 compression for the subset
                  "node"              ; run the pinned Temml converter
                  "make"              ; Makefile entry points
                  "reuse"              ; REUSE license checks in make check
                  "curl"              ; fetch-fonts.sh and axe-core bootstrap
                  "ungoogled-chromium")))) ; browser audits in make check
