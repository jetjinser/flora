;;; SPDX-FileCopyrightText: 2026 Jinser Kafka <aimer@purejs.icu>
;;; SPDX-License-Identifier: GPL-3.0-or-later

(define-module (flora figure-assets)
  #:use-module (grove cache)
  #:use-module (grove output)
  #:use-module (grove pipeline)
  #:use-module (grove render html image)
  #:use-module (ice-9 binary-ports)
  #:use-module (ice-9 format)
  #:use-module (ice-9 ftw)
  #:use-module (ice-9 textual-ports)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:export (make-blazek2005-figure-assets))

(define (make-blazek2005-figure-assets root)
  (let* ((pdf
          (string-append
           root "/materials/books/Computational Fluid Dynamics Principles and Appl.pdf"))
         (manifest (string-append root "/docs/blazek2005-figures.tsv"))
         (cache-root (string-append (or (getenv "TMPDIR") "/tmp") "/flora-figure-pages"))
         (rasterizer-version "pdftoppm-png-200dpi-v1")
         (image-tool
          (if (zero? (system "magick -version >/dev/null 2>&1")) "magick" "convert"))
         (figures (read-figure-manifest manifest)))
    (define pipeline
      (make-asset-pipeline
       #:name "blazek2005-figures"
       #:version "pdftoppm-png-200dpi-imagemagick-avifenc-v1"
       #:inputs (list pdf manifest)
       #:procedure
       (lambda (in)
         (let* ((input-pdf (in pdf))
                (page-cache
                 (string-append cache-root "/"
                   (content-fingerprint
                    (string-append rasterizer-version "\n"
                                   (file-fingerprint input-pdf))))))
           (unless (file-exists? cache-root) (mkdir cache-root))
           (append-map
            (lambda (figure)
              (let* ((name (car figure))
                     (box (cdr figure))
                     (page (list-ref box 0))
                     (x (list-ref box 1))
                     (y (list-ref box 2))
                     (w (list-ref box 3))
                     (h (list-ref box 4))
                     (page-png (render-page input-pdf page page-cache))
                     (cropped (string-append cache-root "/crop-" name)))
                (unless (zero? (system* image-tool page-png "-crop"
                                        (format #f "~ax~a+~a+~a" w h x y)
                                        "+repage" cropped))
                  (error "figure crop failed" name))
                (let* ((base (string-drop-right name 4))
                       (png (string-append "blazek2005/" name))
                       (avif (string-append "blazek2005/" base ".avif")))
                  (list
                   (make-byte-artifact png
                     (call-with-input-file cropped get-bytevector-all))
                   (make-byte-artifact avif
                     (encode-variant cache-root "avifenc"
                       (list "-q" "60" "-s" "8" cropped) avif))))))
            (read-figure-manifest (in manifest)))))))
    (define image-sets
      (map (lambda (entry)
             (let* ((name (car entry))
                    (base (string-drop-right name 4)))
               (make-image-set
                (string-append "blazek2005/" name)
                #:variants
                (list (make-image-variant "image/avif"
                        (string-append "/blazek2005/" base ".avif")))
                #:fallback (string-append "/blazek2005/" name))))
           figures))
    (values pipeline image-sets)))

(define (read-figure-manifest path)
  ;; name page x y width height at 200 dpi; PDF page = printed page + 21.
  (filter-map
   (lambda (line)
     (and (not (string-null? line))
          (not (string-prefix? "#" line))
          (let ((fields (string-split line #\tab)))
            (cons (car fields) (map string->number (cdr fields))))))
   (string-split (call-with-input-file path get-string-all) #\newline)))

(define (render-page pdf page cache-directory)
  ;; pdftoppm names pages with zero-padded page numbers; rasterize each once.
  (let* ((padded (format #f "~3,'0d" page))
         (cached (string-append cache-directory "/p" padded ".png"))
         (prefix (string-append cache-directory "/tmp" padded)))
    (unless (file-exists? cached)
      (unless (file-exists? cache-directory) (mkdir cache-directory))
      (unless (zero? (system* "pdftoppm" "-png" "-r" "200"
                              "-f" (number->string page)
                              "-l" (number->string page)
                              pdf prefix))
        (error "pdftoppm failed" page))
      (rename-file (string-append prefix "-" padded ".png") cached))
    cached))

(define (encode-variant cache-root command args output)
  (let ((temporary (string-append cache-root "/" (basename output))))
    (unless (zero? (apply system* command (append args (list temporary))))
      (error "image encode failed" command output))
    (let ((bytes (call-with-input-file temporary get-bytevector-all #:binary #t)))
      (delete-file temporary)
      bytes)))
