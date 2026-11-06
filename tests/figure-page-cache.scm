;;; SPDX-FileCopyrightText: 2026 Jinser Kafka <aimer@purejs.icu>
;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;

(use-modules (flora figure-assets)
             (grove output)
             (grove private pipeline)
             (ice-9 ftw)
             (ice-9 textual-ports)
             (rnrs bytevectors)
             (srfi srfi-1)
             (srfi srfi-11)
             (srfi srfi-13)
             (srfi srfi-64))

(define test-root (mkdtemp "/tmp/flora-figure-graph-test-XXXXXX"))
(define store (string-append test-root "/store"))
(define fake-bin (string-append test-root "/bin"))
(define pdf (string-append test-root "/materials/books/Computational Fluid Dynamics Principles and Appl.pdf"))
(define manifest (string-append test-root "/docs/blazek2005-figures.tsv"))
(define raster-calls (string-append test-root "/raster-calls"))
(define crop-calls (string-append test-root "/crop-calls"))
(define encode-calls (string-append test-root "/encode-calls"))
(define original-path (getenv "PATH"))
(define original-store (getenv "GROVE_STORE_DIR"))
(define original-cache (getenv "GROVE_CACHE_DIR"))

(define (write-file path content)
  (call-with-output-file path (lambda (port) (display content port))))

(define (read-text path)
  (call-with-input-file path get-string-all))

(define (line-count path)
  (count (lambda (character) (char=? character #\newline))
         (string->list (read-text path))))

(define (make-script path contents)
  (write-file path contents)
  (chmod path #o755))

(define (run-graph pipelines)
  (car (run-asset-pipelines pipelines "flora-figure-graph-test")))

(define (output-content artifacts path)
  (utf8->string
   (artifact-content (find (lambda (artifact)
                             (string=? path (artifact-path artifact)))
                           artifacts))))

(test-begin "Flora figure pipeline graph")
(dynamic-wind
  (lambda ()
    (mkdir fake-bin)
    (mkdir (string-append test-root "/materials"))
    (mkdir (string-append test-root "/materials/books"))
    (mkdir (string-append test-root "/docs"))
    (write-file pdf "pdf revision one")
    (write-file manifest
      (string-append "fig-a.png\t1\t0\t0\t10\t10\n"
                     "fig-b.png\t1\t10\t0\t10\t10\n"))
    (for-each (lambda (path) (write-file path ""))
              (list raster-calls crop-calls encode-calls))
    (make-script (string-append fake-bin "/pdftoppm")
      (string-append
       "#!/bin/sh\n"
       "prefix=\n"
       "while [ \"$#\" -gt 0 ]; do prefix=$1; shift; done\n"
       "printf 'raster\\n' >> '" raster-calls "'\n"
       "printf 'same rendered page' > \"$prefix-001.png\"\n"))
    (make-script (string-append fake-bin "/magick")
      (string-append
       "#!/bin/sh\n"
       "if [ \"$1\" = '-version' ]; then exit 0; fi\n"
       "printf 'crop\\n' >> '" crop-calls "'\n"
       "printf 'crop:%s:%s' \"$3\" \"$(cat \"$1\")\" > \"$5\"\n"))
    (make-script (string-append fake-bin "/avifenc")
      (string-append
       "#!/bin/sh\n"
       "printf 'encode\\n' >> '" encode-calls "'\n"
       "printf 'avif:%s' \"$(cat \"$5\")\" > \"$6\"\n"))
    (setenv "PATH" (string-append fake-bin ":" original-path))
    (setenv "GROVE_STORE_DIR" store)
    (setenv "GROVE_CACHE_DIR" (string-append test-root "/cache")))
  (lambda ()
    (let-values (((pipelines image-sets)
                  (make-blazek2005-figure-assets test-root)))
      (test-equal "two figures on one PDF page form one shared producer and two consumers"
        4 (length pipelines))
      (test-equal "each figure retains its PNG and AVIF image-set mapping"
        2 (length image-sets))
      (let* ((outputs (run-graph pipelines))
             (paths (sort (map artifact-path outputs) string<?)))
        (test-equal "page intermediates stay private while all figure variants publish"
          '("blazek2005/fig-a.avif" "blazek2005/fig-a.png"
            "blazek2005/fig-b.avif" "blazek2005/fig-b.png")
          paths)
        (test-equal "first build rasterizes a shared PDF page once" 1
          (line-count raster-calls))
        (test-equal "both figure consumers crop from the shared page" 2
          (line-count crop-calls))
        (test-equal "both figure consumers encode AVIF variants" 2
          (line-count encode-calls))
        (test-equal "the first figure receives its crop"
          "crop:10x10+0+0:same rendered page"
          (output-content outputs "blazek2005/fig-a.png"))
        (test-equal "the second figure receives its own crop"
          "crop:10x10+10+0:same rendered page"
          (output-content outputs "blazek2005/fig-b.png"))
        (run-graph pipelines)
        (test-equal "warm build reuses the page and both figure consumers"
          '(1 2 2)
          (list (line-count raster-calls)
                (line-count crop-calls)
                (line-count encode-calls)))
        (write-file pdf "pdf revision two")
        (run-graph pipelines)
        (test-equal "changed PDF input reruns its page producer"
          2 (line-count raster-calls))
        (test-equal "identical page bytes preserve both consumer cache entries"
          '(2 2)
          (list (line-count crop-calls) (line-count encode-calls)))
        (write-file manifest
          (string-append "fig-a.png\t1\t1\t0\t10\t10\n"
                         "fig-b.png\t1\t10\t0\t10\t10\n"))
        (let ((updated (run-graph pipelines)))
          (test-equal "manifest changes leave the page producer cached"
            2 (line-count raster-calls))
          (test-equal "one changed manifest record invalidates only its figure consumer"
            '(3 3) (list (line-count crop-calls) (line-count encode-calls)))
          (test-equal "changed crop coordinates change the first image"
            "crop:10x10+1+0:same rendered page"
            (output-content updated "blazek2005/fig-a.png"))
          (test-equal "an unaffected figure keeps its image bytes"
            "crop:10x10+10+0:same rendered page"
            (output-content updated "blazek2005/fig-b.png"))))))
  (lambda ()
    (if original-path (setenv "PATH" original-path) (unsetenv "PATH"))
    (if original-store
        (setenv "GROVE_STORE_DIR" original-store)
        (unsetenv "GROVE_STORE_DIR"))
    (if original-cache
        (setenv "GROVE_CACHE_DIR" original-cache)
        (unsetenv "GROVE_CACHE_DIR"))
    (system* "rm" "-rf" test-root)))

(define failures (+ (test-runner-fail-count (test-runner-current))
                    (test-runner-xpass-count (test-runner-current))))
(test-end "Flora figure pipeline graph")
(exit (if (zero? failures) 0 1))
