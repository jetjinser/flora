;;; SPDX-FileCopyrightText: 2026 Jinser Kafka <aimer@purejs.icu>
;;;
;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;
;;; Run from Flora's root inside its Guix environment:
;;;   guile --no-auto-compile tests/figure-page-cache.scm

(use-modules (grove cache)
             (ice-9 ftw)
             (ice-9 textual-ports)
             (srfi srfi-1)
             (srfi srfi-13)
             (srfi srfi-64))

(load "../project.scm")

(define test-root (mkdtemp "/tmp/flora-page-cache-test-XXXXXX"))
(define test-cache (string-append test-root "/cache"))
(define fake-bin (string-append test-root "/bin"))
(define fake-rasterizer (string-append fake-bin "/pdftoppm"))
(define input-a (string-append test-root "/input-a.pdf"))
(define input-b (string-append test-root "/input-b.pdf"))
(define calls-file (string-append test-root "/calls"))
(define original-cache figure-page-cache)
(define original-path (getenv "PATH"))

(define (read-text path)
  (call-with-input-file path get-string-all))

(define (render-page-one pdf)
  (render-page
   pdf 1
   (string-append
    figure-page-cache "/"
    (content-fingerprint
     (string-append figure-page-rasterizer-version "\n"
                    (file-fingerprint pdf))))))

(test-begin "Flora figure page cache")
(dynamic-wind
  (lambda ()
    (mkdir test-cache)
    (mkdir fake-bin)
    (call-with-output-file input-a
      (lambda (port) (display "pdf-a" port)))
    (call-with-output-file input-b
      (lambda (port) (display "pdf-b" port)))
    (call-with-output-file fake-rasterizer
      (lambda (port)
        (format port
          "#!/bin/sh\ninput=\nprefix=\nwhile [ \"$#\" -gt 0 ]; do\n  case \"$1\" in *.pdf) input=$1;; esac\n  prefix=$1\n  shift\ndone\nprintf '%s\\n' called >> '~a'\ncase \"$input\" in *input-a.pdf) raster=from-pdf-a;; *) raster=from-pdf-b;; esac\nprintf '%s' \"$raster\" > \"$prefix-001.png\"\n"
          calls-file)))
    (chmod fake-rasterizer #o755)
    (set! figure-page-cache test-cache)
    (setenv "PATH" (string-append fake-bin ":" original-path)))
  (lambda ()
    (let* ((a-path (render-page-one input-a))
           (a-content (read-text a-path))
           (a-path-again (render-page-one input-a))
           (b-path (render-page-one input-b))
           (b-content (read-text b-path))
           (calls (count (lambda (character) (char=? character #\newline))
                         (string->list (read-text calls-file)))))
      (test-equal "a PDF's page raster is cached" "from-pdf-a" a-content)
      (test-equal "an unchanged PDF reuses the same page raster" a-path a-path-again)
      (test-assert "a different PDF gets a separate page cache" 
        (not (string=? a-path b-path)))
      (test-equal "each distinct PDF is rasterized once" 2 calls)
      (test-equal "the second PDF cannot reuse the first PDF's raster"
        "from-pdf-b" b-content)))
  (lambda ()
    (set! figure-page-cache original-cache)
    (if original-path
        (setenv "PATH" original-path)
        (unsetenv "PATH"))
    (system* "rm" "-rf" test-root)))

(define failures (+ (test-runner-fail-count (test-runner-current))
                    (test-runner-xpass-count (test-runner-current))))
(test-end "Flora figure page cache")
(exit (if (zero? failures) 0 1))
