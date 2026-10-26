;;; SPDX-FileCopyrightText: 2026 Jinser Kafka <aimer@purejs.icu>
;;; SPDX-License-Identifier: GPL-3.0-or-later

(define-module (flora entity-snapshot)
  #:use-module (grove cache)
  #:use-module (ice-9 format)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-19)
  #:export (store-entity-snapshot!))

(define (without-capture-time datum)
  (filter (lambda (field)
            (not (memq (car field) '(captured-at fetched-at))))
          datum))

(define (write-datum-atomically path datum)
  (let ((temporary (format #f "~a.tmp.~a" path (getpid))))
    (call-with-output-file temporary
      (lambda (port)
        (write datum port)
        (newline port)))
    (rename-file temporary path)))

(define (read-index path)
  (if (file-exists? path)
      (call-with-input-file path read)
      '()))

(define (store-entity-snapshot! root uri datum)
  (unless (and (string? uri)
               (list? datum)
               (equal? uri (assq-ref datum 'uri)))
    (error "entity snapshot must declare its requested URI" uri datum))
  (let* ((directory (string-append root "/metadata/entities"))
         (index-path (string-append directory "/index.scm"))
         (relative-path
          (string-append "metadata/entities/" (content-fingerprint uri) ".scm"))
         (snapshot-path (string-append root "/" relative-path)))
    (unless (file-exists? (string-append root "/metadata"))
      (mkdir (string-append root "/metadata")))
    (unless (file-exists? directory) (mkdir directory))
    (let* ((old-index (read-index index-path))
           (old-snapshot
            (and (file-exists? snapshot-path)
                 (call-with-input-file snapshot-path read)))
           (content (without-capture-time datum))
           (snapshot-changed?
            (or (not old-snapshot)
                (not (assq 'captured-at old-snapshot))
                (not (equal? content (without-capture-time old-snapshot)))))
           (snapshot
            (if snapshot-changed?
                (append content
                        (list (cons 'captured-at
                                    (date->string (current-date 0)
                                                  "~Y-~m-~dT~H:~M:~SZ"))))
                old-snapshot))
           (updated-index
            (sort (cons (cons uri relative-path)
                        (filter (lambda (entry)
                                  (not (string=? (car entry) uri)))
                                old-index))
                  (lambda (left right)
                    (string<? (car left) (car right)))))
           (index-changed? (not (equal? old-index updated-index))))
      (when snapshot-changed?
        (write-datum-atomically snapshot-path snapshot))
      (when index-changed?
        (write-datum-atomically index-path updated-index))
      (values (if snapshot-changed? 'updated 'unchanged) snapshot-path))))
