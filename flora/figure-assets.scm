;;; SPDX-FileCopyrightText: 2026 Jinser Kafka <aimer@purejs.icu>
;;; SPDX-License-Identifier: GPL-3.0-or-later

(define-module (flora figure-assets)
  #:use-module (grove output)
  #:use-module (grove pipeline)
  #:use-module (grove render html image)
  #:use-module (ice-9 binary-ports)
  #:use-module (ice-9 format)
  #:use-module (ice-9 ftw)
  #:use-module (ice-9 popen)
  #:use-module (ice-9 textual-ports)
  #:use-module (rnrs bytevectors)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:export (make-blazek2005-figure-assets))

(define (make-blazek2005-figure-assets root)
  (let* ((pdf
          (string-append
           root "/materials/books/Computational Fluid Dynamics Principles and Appl.pdf"))
         (manifest (string-append root "/docs/blazek2005-figures.tsv"))
         (image-tool
          (if (zero? (system "magick -version >/dev/null 2>&1")) "magick" "convert"))
         (figures (read-figure-manifest manifest))
         (pages (delete-duplicates (map (lambda (figure) (cadr figure))
                                        figures)))
         (page-pipelines
          (map (lambda (page)
                 (cons page (make-pdf-page-pipeline pdf page)))
               pages))
         (metadata-pipeline (make-figure-metadata-pipeline manifest))
         (figure-pipelines
          (map (lambda (figure)
                 (make-figure-pipeline figure page-pipelines metadata-pipeline
                                       image-tool))
               figures))
         (image-sets (map make-figure-image-set figures)))
    (values (append (map cdr page-pipelines)
                    (list metadata-pipeline)
                    figure-pipelines)
            image-sets)))

(define (make-figure-metadata-pipeline manifest)
  (make-asset-pipeline
   #:name "blazek2005-figure-metadata"
   #:version "figure-manifest-records-v1"
   #:inputs (list manifest)
   #:procedure
   (lambda (in)
     (map (lambda (figure)
            (make-byte-artifact
             (figure-metadata-artifact-path (car figure))
             (string->utf8
              (string-join (map number->string (cddr figure)) "\t"))))
          (read-figure-manifest (in manifest))))))

(define (make-figure-pipeline figure page-pipelines metadata-pipeline image-tool)
  (let* ((name (car figure))
         (page (cadr figure))
         (page-producer (cdr (assoc page page-pipelines)))
         (page-reference
          (pipeline-output page-producer (pdf-page-artifact-path page)))
         (metadata-reference
          (pipeline-output metadata-pipeline
                           (figure-metadata-artifact-path name))))
    (make-asset-pipeline
     #:name (string-append "blazek2005-figure-" name)
     #:version "imagemagick-crop-avifenc-q60-s8-v1"
     #:inputs (list page-reference metadata-reference)
     #:procedure
     (lambda (in)
       (let* ((page-png (in page-reference))
              (box
               (map string->number
                    (string-split (call-with-input-file (in metadata-reference)
                                    get-string-all)
                                  #\tab)))
              (x (list-ref box 0))
              (y (list-ref box 1))
              (w (list-ref box 2))
              (h (list-ref box 3))
              (base (string-drop-right name 4))
              (png (string-append "blazek2005/" name))
              (avif (string-append "blazek2005/" base ".avif")))
         (call-with-temporary-directory
          "flora-figure-crop"
          (lambda (directory)
            (let ((cropped (string-append directory "/crop.png")))
              (unless (zero? (system* image-tool page-png "-crop"
                                      (format #f "~ax~a+~a+~a" w h x y)
                                      "+repage" cropped))
                (error "figure crop failed" name))
              (list
               (make-byte-artifact
                png
                (call-with-input-file cropped get-bytevector-all #:binary #t))
               (make-byte-artifact
                avif
                (encode-variant directory "avifenc"
                  (list "-q" "60" "-s" "8" cropped))))))))))))

(define (figure-metadata-artifact-path name)
  (format #f "private/blazek2005/figure-metadata/~a.tsv"
          (string-drop-right name 4)))

(define (make-figure-image-set figure)
  (let* ((name (car figure))
         (base (string-drop-right name 4)))
    (make-image-set
     (string-append "blazek2005/" name)
     #:variants
     (list (make-image-variant "image/avif"
             (string-append "/blazek2005/" base ".avif")))
     #:fallback (string-append "/blazek2005/" name))))

(define (read-figure-manifest path)
  ;; name page x y width height at 200 dpi; PDF page = printed page + 21.
  (filter-map
   (lambda (line)
     (and (not (string-null? line))
          (not (string-prefix? "#" line))
          (let ((fields (string-split line #\tab)))
            (cons (car fields) (map string->number (cdr fields))))))
   (string-split (call-with-input-file path get-string-all) #\newline)))

(define (pdf-page-artifact-path page)
  (format #f "private/blazek2005/pdf-page-~a.png" page))

(define (make-pdf-page-pipeline pdf page)
  (make-asset-pipeline
   #:name (format #f "blazek2005-pdf-page-~a" page)
   #:version "pdftoppm-png-200dpi-v1"
   #:inputs (list pdf)
   #:procedure
   (lambda (in)
     (let* ((input-pdf (in pdf))
            (padded (format #f "~3,'0d" page)))
       (call-with-temporary-directory
        "flora-pdf-page"
        (lambda (directory)
          (let* ((prefix (string-append directory "/page"))
                 (png (string-append prefix "-" padded ".png")))
            (unless (zero? (system* "pdftoppm" "-png" "-r" "200"
                                    "-f" (number->string page)
                                    "-l" (number->string page)
                                    input-pdf prefix))
              (error "pdftoppm failed" page))
            (list (make-byte-artifact
                   (pdf-page-artifact-path page)
                   (call-with-input-file png get-bytevector-all #:binary #t))))))))))

(define (call-with-temporary-directory name procedure)
  (let ((directory
         (mkdtemp (string-append (or (getenv "TMPDIR") "/tmp") "/"
                                 name "-XXXXXX"))))
    (dynamic-wind
      (lambda () #t)
      (lambda () (procedure directory))
      (lambda () (remove-temporary-tree directory)))))

(define (remove-temporary-tree path)
  (let ((info (false-if-exception (lstat path))))
    (when info
      (if (eq? (stat:type info) 'directory)
          (begin
            (for-each
             (lambda (name)
               (unless (member name '("." ".."))
                 (remove-temporary-tree (string-append path "/" name))))
             (scandir path))
            (rmdir path))
          (delete-file path)))))

(define (encode-variant directory command args)
  (let* ((temporary (string-append directory "/variant.avif"))
         (process
          (apply open-pipe* OPEN_READ command (append args (list temporary)))))
    ;; avifenc prints a full report for every successful image to stdout.
    ;; Drain it quietly; stderr and the process status remain visible to users.
    (let drain ()
      (unless (eof-object? (read-char process))
        (drain)))
    (unless (zero? (close-pipe process))
      (error "image encode failed" command temporary))
    (call-with-input-file temporary get-bytevector-all #:binary #t)))
