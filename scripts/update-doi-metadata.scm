;;; SPDX-FileCopyrightText: 2026 Jinser Kafka <aimer@purejs.icu>
;;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Explicitly refresh one DOI metadata snapshot. Ordinary site builds only
;;; read the resulting local Scheme data file and never make network requests.

(use-modules (flora entity-snapshot)
             (ice-9 format)
             (ice-9 textual-ports)
             (json)
             (srfi srfi-1)
             (srfi srfi-11)
             (srfi srfi-13))

(define (command-error message)
  (format (current-error-port) "update-doi-metadata: ~a~%" message)
  (exit 2))

(define arguments (cdr (command-line)))
(unless (= (length arguments) 1)
  (command-error "usage: update-doi-metadata.scm doi:10.../..."))

(define uri (car arguments))
(unless (string-prefix? "doi:" uri)
  (command-error (format #f "expected a DOI URI beginning with doi: ~s" uri)))
(define doi (substring uri 4))
(unless (and (string-prefix? "10." doi)
             (string-index doi #\/)
             (string-every
               (lambda (character)
                 (or (char-alphabetic? character)
                     (char-numeric? character)
                     (memv character '(#\. #\/ #\- #\_ #\~ #\! #\$ #\&
                                       #\' #\( #\) #\* #\+ #\, #\; #\= #\@))))
               doi))
  (command-error (format #f "DOI contains unsupported URI path characters: ~s" doi)))

(define temporary-path
  (format #f "/tmp/flora-doi-~a.json" (getpid)))
(define request-url (string-append "https://doi.org/" doi))

(define (update-error message)
  (throw 'update-error message))

(define (json-field record key)
  (and (list? record) (assoc-ref record key)))

(define (first-string value)
  (cond ((string? value) value)
        ((and (vector? value) (> (vector-length value) 0)
              (string? (vector-ref value 0)))
         (vector-ref value 0))
        (else #f)))

(define (author-name author)
  (let ((name (json-field author "name"))
        (given (json-field author "given"))
        (family (json-field author "family")))
    (if (and (string? name) (not (string-null? name)))
        name
        (string-join (filter string? (list given family)) " "))))

(define (authors record)
  (let ((values (json-field record "author")))
    (if (vector? values)
        (filter-map (lambda (author)
                      (let ((name (author-name author)))
                        (and (not (string-null? name)) name)))
                    (vector->list values))
        '())))

(define (issued-year record)
  (let* ((issued (json-field record "issued"))
         (parts (and issued (json-field issued "date-parts")))
         (date (and (vector? parts) (> (vector-length parts) 0)
                    (vector-ref parts 0))))
    (and (vector? date) (> (vector-length date) 0)
         (number->string (vector-ref date 0)))))

(define (read-response)
  (catch #t
    (lambda ()
      (call-with-input-file temporary-path json->scm))
    (lambda _
      (update-error (format #f "response for ~a was not valid JSON" uri)))))

(define (fetch)
  (let ((status
         (system* "curl" "--fail" "--silent" "--show-error" "--location"
                  "--max-time" "45"
                  "--header" "Accept: application/vnd.citationstyles.csl+json"
                  "--output" temporary-path request-url)))
    (unless (and (number? status) (zero? status))
      (update-error
        (format #f "request for ~a failed; check connectivity and DOI availability" uri))))
  (let* ((record (read-response))
         (record-doi (json-field record "DOI"))
         (title (first-string (json-field record "title")))
         (record-authors (authors record))
         (year (issued-year record)))
    (unless (and (string? record-doi) (string-ci=? doi record-doi)
                 title)
      (update-error
        (format #f "response DOI ~s did not match ~a or had no title"
                record-doi uri)))
    `((uri . ,uri)
      (type . citation)
      (source . "https://doi.org/ (CSL-JSON content negotiation)")
      (title . ,title)
      (authors . ,record-authors)
      (year . ,year)
      (container-title . ,(first-string (json-field record "container-title")))
      (publisher . ,(json-field record "publisher")))))

(catch 'update-error
  (lambda ()
    (dynamic-wind
      (lambda () #t)
      (lambda ()
        (let-values (((status path)
                      (store-entity-snapshot! (getcwd) uri (fetch))))
          (format #t "~a ~a from DOI content negotiation: ~a~%"
                  (if (eq? status 'updated) "Updated" "Unchanged")
                  uri path)))
      (lambda ()
        (when (file-exists? temporary-path)
          (delete-file temporary-path)))))
  (lambda (_ message)
    (format (current-error-port) "update-doi-metadata: ~a~%" message)
    (exit 1)))
