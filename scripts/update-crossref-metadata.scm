;;; SPDX-FileCopyrightText: 2026 Jinser Kafka <aimer@purejs.icu>
;;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Refresh a citation snapshot from Crossref's public REST API. Site builds
;;; only read the resulting Scheme data; they never contact Crossref.

(use-modules (flora private doi)
             (flora entity-snapshot)
             (ice-9 format)
             (ice-9 textual-ports)
             (json)
             (srfi srfi-1)
             (srfi srfi-11)
             (srfi srfi-13))

(define (command-error message)
  (format (current-error-port) "update-crossref-metadata: ~a~%" message)
  (exit 2))

(define arguments (cdr (command-line)))
(unless (= (length arguments) 1)
  (command-error "usage: update-crossref-metadata.scm doi:10.../..."))

(define uri (car arguments))
(define doi (doi-iri-name uri))
(unless doi
  (command-error
    (format #f "expected a valid doi: IRI with a 10.xxxx/... name: ~s" uri)))

(define temporary-path
  (format #f "/tmp/flora-crossref-~a.json" (getpid)))
(define api-url
  (doi-request-url "https://api.crossref.org/works/" doi))

(define (update-error message)
  (throw 'update-error message))

(define (field record key)
  (and (list? record) (assoc-ref record key)))

(define (first-string value)
  (cond ((string? value) value)
        ((and (vector? value) (> (vector-length value) 0)
              (string? (vector-ref value 0)))
         (vector-ref value 0))
        (else #f)))

(define (author-name author)
  (let ((name (field author "name"))
        (given (field author "given"))
        (family (field author "family")))
    (if (and (string? name) (not (string-null? name)))
        name
        (string-join (filter string? (list given family)) " "))))

(define (authors record)
  (let ((values (field record "author")))
    (if (vector? values)
        (filter-map (lambda (author)
                      (let ((name (author-name author)))
                        (and (not (string-null? name)) name)))
                    (vector->list values))
        '())))

(define (published-year record)
  (let* ((date (or (field record "published")
                   (field record "published-print")
                   (field record "published-online")
                   (field record "created")))
         (parts (and date (field date "date-parts")))
         (first-date (and (vector? parts) (> (vector-length parts) 0)
                          (vector-ref parts 0))))
    (and (vector? first-date) (> (vector-length first-date) 0)
         (number? (vector-ref first-date 0))
         (number->string (vector-ref first-date 0)))))

(define (read-response)
  (catch #t
    (lambda () (call-with-input-file temporary-path json->scm))
    (lambda _
      (update-error (format #f "response for ~a was not valid JSON" uri)))))

(define (fetch)
  (let ((status
         (system* "curl" "--fail" "--silent" "--show-error" "--location"
                  "--max-time" "45" "--header" "Accept: application/json"
                  "--output" temporary-path api-url)))
    (unless (and (number? status) (zero? status))
      (update-error
        (format #f "request for ~a failed; check connectivity and DOI availability" uri))))
  (let* ((response (read-response))
         (record (field response "message"))
         (record-doi (field record "DOI"))
         (title (first-string (field record "title")))
         (record-authors (authors record)))
    (unless (and (string? record-doi) (doi-name=? doi record-doi)
                 title (not (string-null? title)))
      (update-error
        (format #f "Crossref response DOI ~s did not match ~a or had no title"
                record-doi uri)))
    `((uri . ,uri)
      (type . citation)
      (source . ,api-url)
      (title . ,title)
      (authors . ,record-authors)
      (year . ,(published-year record))
      (container-title . ,(first-string (field record "container-title")))
      (publisher . ,(field record "publisher")))))

(catch 'update-error
  (lambda ()
    (dynamic-wind
      (lambda () #t)
      (lambda ()
        (let-values (((status path)
                      (store-entity-snapshot! (getcwd) uri (fetch))))
          (format #t "~a ~a from Crossref REST API: ~a~%"
                  (if (eq? status 'updated) "Updated" "Unchanged") uri path)))
      (lambda ()
        (when (file-exists? temporary-path) (delete-file temporary-path)))))
  (lambda (_ message)
    (format (current-error-port) "update-crossref-metadata: ~a~%" message)
    (exit 1)))
