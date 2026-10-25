;;; SPDX-FileCopyrightText: 2026 Jinser Kafka <aimer@purejs.icu>
;;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Explicitly refresh one DOI metadata snapshot. Ordinary site builds only
;;; read the resulting local Scheme data file and never make network requests.

(use-modules (grove cache)
             (ice-9 format)
             (ice-9 textual-ports)
             (json)
             (srfi srfi-1)
             (srfi srfi-13)
             (srfi srfi-19))

(define arguments (cdr (command-line)))
(unless (= (length arguments) 1)
  (error "usage: update-doi-metadata.scm doi:10.../..."))

(define uri (car arguments))
(unless (string-prefix? "doi:" uri)
  (error "expected a DOI URI beginning with doi:" uri))
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
  (error "DOI contains unsupported URI path characters" doi))

(define directory "metadata/dois")
(define index-path (string-append directory "/index.scm"))
(define snapshot-path
  (string-append directory "/" (content-fingerprint uri) ".scm"))
(define temporary-path
  (format #f "/tmp/flora-doi-~a.json" (getpid)))
(define request-url (string-append "https://doi.org/" doi))

(define (json-field record key)
  (and (list? record) (assoc-ref record key)))

(define (first-string value)
  (cond ((string? value) value)
        ((and (vector? value) (> (vector-length value) 0)
              (string? (vector-ref value 0)))
         (vector-ref value 0))
        (else #f)))

(define (author-name author)
  (let ((given (json-field author "given"))
        (family (json-field author "family")))
    (string-join (filter string? (list given family)) " ")))

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

(define (existing-index)
  (if (file-exists? index-path)
      (call-with-input-file index-path read)
      '()))

(define (read-response)
  (call-with-input-file temporary-path json->scm))

(define (write-datum-atomically path datum)
  (let ((temporary (string-append path ".tmp")))
    (call-with-output-file temporary
      (lambda (port)
        (write datum port)
        (newline port)))
    (rename-file temporary path)))

(define (fetch)
  (let ((status
         (system* "curl" "--fail" "--silent" "--show-error" "--location"
                  "--max-time" "45"
                  "--header" "Accept: application/vnd.citationstyles.csl+json"
                  "--output" temporary-path request-url)))
    (unless (and (number? status) (zero? status))
      (error "DOI metadata request failed" uri status)))
  (let* ((record (read-response))
         (record-doi (json-field record "DOI"))
         (title (first-string (json-field record "title")))
         (record-authors (authors record))
         (year (issued-year record)))
    (unless (and (string? record-doi) (string-ci=? doi record-doi)
                 title)
      (error "DOI response did not contain the requested CSL record"
             uri record-doi title))
    `((uri . ,uri)
      (source . "https://doi.org/ (CSL-JSON content negotiation)")
      (fetched-at . ,(date->string (current-date 0) "~Y-~m-~dT~H:~M:~SZ"))
      (title . ,title)
      (authors . ,record-authors)
      (year . ,year)
      (container-title . ,(first-string (json-field record "container-title")))
      (publisher . ,(json-field record "publisher")))))

(unless (file-exists? directory)
  (mkdir directory))
(dynamic-wind
  (lambda () #t)
  (lambda ()
    (let* ((snapshot (fetch))
           (index (filter (lambda (entry)
                            (not (string=? (car entry) uri)))
                          (existing-index)))
           (updated (sort (cons (cons uri snapshot-path) index)
                          (lambda (left right)
                            (string<? (car left) (car right))))))
      (write-datum-atomically snapshot-path snapshot)
      (write-datum-atomically index-path updated)
      (format #t "Updated ~a from DOI content negotiation: ~a~%"
              uri snapshot-path)))
  (lambda ()
    (when (file-exists? temporary-path)
      (delete-file temporary-path))))
