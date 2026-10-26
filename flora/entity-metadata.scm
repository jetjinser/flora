;;; SPDX-FileCopyrightText: 2026 Jinser Kafka <aimer@purejs.icu>
;;; SPDX-License-Identifier: GPL-3.0-or-later

(define-module (flora entity-metadata)
  #:use-module (srfi srfi-1)
  #:export (load-entity-metadata
            entity-metadata-source-paths
            entity-metadata-ref))

(define (index-path root)
  (string-append root "/metadata/entities/index.scm"))

(define (read-index root)
  (let ((path (index-path root)))
    (if (file-exists? path)
        (call-with-input-file path read)
        '())))

(define (snapshot-path root relative-path)
  (string-append root "/" relative-path))

(define (entity-metadata-source-paths root)
  (let ((index (read-index root)))
    (cons (index-path root)
          (map (lambda (entry)
                 (snapshot-path root (cdr entry)))
               index))))

(define (load-entity-metadata root)
  (map (lambda (entry)
         (let* ((uri (car entry))
                (snapshot (call-with-input-file
                              (snapshot-path root (cdr entry))
                            read)))
           (unless (and (list? snapshot)
                        (equal? uri (assq-ref snapshot 'uri)))
             (error "entity metadata snapshot URI does not match its index"
                    uri snapshot))
           (cons uri snapshot)))
       (read-index root)))

(define (entity-metadata-ref metadata uri)
  (let ((entry (assoc uri metadata string=?)))
    (and entry (cdr entry))))
