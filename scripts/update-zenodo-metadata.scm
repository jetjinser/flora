;;; SPDX-FileCopyrightText: 2026 Jinser Kafka <aimer@purejs.icu>
;;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Refresh a local snapshot for a public Zenodo record. Site builds only read
;;; the resulting Scheme data; they never contact Zenodo.

(use-modules (grove cache)
             (htmlprag)
             (ice-9 format)
             (ice-9 textual-ports)
             (json)
             (srfi srfi-1)
             (srfi srfi-13)
             (srfi srfi-19))

(define (command-error message)
  (format (current-error-port) "update-zenodo-metadata: ~a~%" message)
  (exit 2))

(define arguments (cdr (command-line)))
(unless (= (length arguments) 1)
  (command-error "usage: update-zenodo-metadata.scm https://zenodo.org/records/ID"))

(define uri (car arguments))
(define prefix "https://zenodo.org/records/")
(unless (string-prefix? prefix uri)
  (command-error (format #f "expected a Zenodo record URI beginning with ~s" prefix)))
(define record-id (substring uri (string-length prefix)))
(unless (and (not (string-null? record-id))
             (string-every char-numeric? record-id))
  (command-error (format #f "expected a numeric record ID in ~s" uri)))

(define directory "metadata/entities")
(define index-path (string-append directory "/index.scm"))
(define snapshot-path
  (string-append directory "/" (content-fingerprint uri) ".scm"))
(define temporary-path
  (format #f "/tmp/flora-zenodo-~a.json" (getpid)))
(define api-url (string-append "https://zenodo.org/api/records/" record-id))

(define (update-error message)
  (throw 'update-error message))

(define (field record key)
  (and (list? record) (assoc-ref record key)))

(define (html-text value)
  (let flatten ((node (html->sxml value)))
    (cond ((string? node) node)
          ((pair? node)
           (let* ((children (if (symbol? (car node)) (cdr node) node))
                  (text (string-concatenate (map flatten children))))
             (if (and (symbol? (car node))
                      (memq (car node) '(p div li br)))
                 (string-append text " ")
                 text)))
          (else ""))))

(define (write-datum-atomically path datum)
  (let ((temporary (string-append path ".tmp")))
    (call-with-output-file temporary
      (lambda (port)
        (write datum port)
        (newline port)))
    (rename-file temporary path)))

(define (without-capture-time datum)
  (filter (lambda (field)
            (not (memq (car field) '(captured-at fetched-at))))
          datum))

(define (existing-index)
  (if (file-exists? index-path)
      (call-with-input-file index-path read)
      '()))

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
        (format #f "request for ~a failed; check connectivity and record availability" uri))))
  (let* ((record (read-response))
         (metadata (field record "metadata"))
         (links (field record "links"))
         (record-uri (field links "self_html"))
         (doi (field record "doi"))
         (title (field metadata "title"))
         (creators (field metadata "creators"))
         (creator-names
          (if (vector? creators)
              (filter-map (lambda (creator)
                            (let ((name (field creator "name")))
                              (and (string? name) name)))
                          (vector->list creators))
              '()))
         (description (field metadata "description"))
         (license (field (field metadata "license") "id"))
         (resource-type (field (field metadata "resource_type") "type")))
    (unless (and (string? record-uri) (string=? uri record-uri)
                 (string? doi) (string-prefix? "10." doi)
                 (string? title) (not (string-null? title))
                 (string? resource-type))
      (update-error
        (format #f "record response did not match ~a or lacked required metadata" uri)))
    `((uri . ,uri)
      (type . ,(if (string=? resource-type "dataset") 'dataset 'resource))
      (source . ,api-url)
      (captured-at . ,(date->string (current-date 0) "~Y-~m-~dT~H:~M:~SZ"))
      (doi . ,doi)
      (name . ,title)
      (creators . ,creator-names)
      (description . ,(and (string? description) (string-trim-both (html-text description))))
      (landing-page . ,record-uri)
      (license . ,license))))

(catch 'update-error
  (lambda ()
    (unless (file-exists? directory) (mkdir directory))
    (dynamic-wind
      (lambda () #t)
      (lambda ()
        (let* ((snapshot (fetch))
               (old-snapshot
                (and (file-exists? snapshot-path)
                     (call-with-input-file snapshot-path read)))
               (snapshot-changed?
                (or (not old-snapshot)
                    (assq 'fetched-at old-snapshot)
                    (not (equal? (without-capture-time old-snapshot)
                                 (without-capture-time snapshot)))))
               (index (filter (lambda (entry) (not (string=? (car entry) uri)))
                              (existing-index)))
               (updated (sort (cons (cons uri snapshot-path) index)
                              (lambda (left right)
                                (string<? (car left) (car right)))))
               (index-changed? (not (equal? updated (existing-index)))))
          (when snapshot-changed? (write-datum-atomically snapshot-path snapshot))
          (when index-changed? (write-datum-atomically index-path updated))
          (format #t "~a ~a from Zenodo record API: ~a~%"
                  (if snapshot-changed? "Updated" "Unchanged") uri snapshot-path)))
      (lambda ()
        (when (file-exists? temporary-path) (delete-file temporary-path)))))
  (lambda (_ message)
    (format (current-error-port) "update-zenodo-metadata: ~a~%" message)
    (exit 1)))
