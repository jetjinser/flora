;;; SPDX-FileCopyrightText: 2026 Jinser Kafka <aimer@purejs.icu>
;;; SPDX-License-Identifier: GPL-3.0-or-later

(define-module (flora private doi)
  #:use-module (srfi :275 iri)
  #:use-module (srfi :275 normalize)
  #:use-module (srfi :275 path)
  #:use-module (srfi :275 uri)
  #:use-module (srfi srfi-13)
  #:export (doi-iri-name
            doi-name=?
            doi-request-url))

(define (doi-iri-name value)
  "Return the DOI name in an absolute doi: IRI, or #f when VALUE is invalid."
  (and (string? value)
       (catch #t
         (lambda ()
           (let* ((iri (string->iri value))
                  (name (path->string (iri-path iri))))
             (and (non-relative-iri? iri)
                  (string-ci=? (iri-scheme iri) "doi")
                  (not (iri-host iri))
                  (not (iri-query iri))
                  (not (iri-fragment iri))
                  (string-prefix? "10." name)
                  (string-index name #\/)
                  name)))
         (lambda _ #f))))

(define (ascii-downcase character)
  (let ((code (char->integer character)))
    (if (and (<= 65 code) (<= code 90))
        (integer->char (+ code 32))
        character)))

(define (doi-name=? left right)
  "Compare DOI names, folding ASCII letters only as DOI equivalence requires."
  (and (string? left)
       (string? right)
       (= (string-length left) (string-length right))
       (let loop ((index 0))
         (or (= index (string-length left))
             (and (char=? (ascii-downcase (string-ref left index))
                          (ascii-downcase (string-ref right index)))
                  (loop (+ index 1)))))))

(define (doi-request-url base name)
  "Append DOI NAME to BASE and map the resulting IRI to a request URI."
  (let* ((iri (string->iri (string-append base name)))
         (uri (iri->uri iri)))
    (uri->string uri)))
