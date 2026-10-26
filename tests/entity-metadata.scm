;;; SPDX-FileCopyrightText: 2026 Jinser Kafka <aimer@purejs.icu>
;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;
;;; Run from Flora's root:
;;;   guile --no-auto-compile -L . tests/entity-metadata.scm

(use-modules (flora entity-metadata)
             (flora entity-presentation)
             (ice-9 ftw)
             (srfi srfi-64))

(define root (mkdtemp "/tmp/flora-entity-metadata-XXXXXX"))
(define directory (string-append root "/metadata/entities"))
(define index-path (string-append directory "/index.scm"))
(define doi-uri "doi:10.1234/example")
(define https-uri "https://example.org/publication/42")
(define doi-path "metadata/entities/doi.scm")
(define https-path "metadata/entities/https.scm")

(define (write-datum path value)
  (call-with-output-file path
    (lambda (port)
      (write value port)
      (newline port))))

(define doi-record
  `((uri . ,doi-uri)
    (type . citation)
    (source . "CSL-JSON content negotiation")
    (captured-at . "2026-01-01T00:00:00Z")
    (title . "A DOI publication")
    (authors . ("Ada Lovelace"))
    (year . "1843")))

(define https-record
  `((uri . ,https-uri)
    (type . dataset)
    (source . "local JSON-LD fixture")
    (captured-at . "2026-01-02T00:00:00Z")
    (name . "Open PIV Benchmark")
    (description . "Velocity-field measurements for particle image velocimetry.")
    (landing-page . "https://example.org/datasets/piv")
    (license . "CC BY 4.0")))

(test-begin "scheme-independent entity metadata snapshots")
(dynamic-wind
  (lambda ()
    (mkdir (string-append root "/metadata"))
    (mkdir directory)
    (write-datum index-path
      (list (cons doi-uri doi-path)
            (cons https-uri https-path)))
    (write-datum (string-append root "/" doi-path) doi-record)
    (write-datum (string-append root "/" https-path) https-record))
  (lambda ()
    (let ((snapshots (load-entity-metadata root))
          (sources (entity-metadata-source-paths root)))
      (test-equal "DOI snapshot loads by its exact entity URI"
        doi-record (entity-metadata-ref snapshots doi-uri))
      (test-equal "HTTPS snapshot loads through the same interface"
        https-record (entity-metadata-ref snapshots https-uri))
      (test-equal "DOI metadata uses the shared presentation adapter"
        '(li (@ (class "meta-item external-metadata"))
             "外部文献：" (cite "A DOI publication") " — " "Ada Lovelace · 1843")
        (entity-metadata-item (entity-metadata-ref snapshots doi-uri)))
      (test-equal "HTTPS dataset metadata gets a dataset presentation"
        '(li (@ (class "meta-item external-metadata dataset"))
             "外部数据集："
             (a (@ (href "https://example.org/datasets/piv"))
                "Open PIV Benchmark")
             " — " "Velocity-field measurements for particle image velocimetry."
             " · 许可：" "CC BY 4.0")
        (entity-metadata-item (entity-metadata-ref snapshots https-uri)))
      (test-assert "unknown entity types have no implicit presentation"
        (not (entity-metadata-item '((type . software)))))
      (test-equal "the index and both snapshots are declared build inputs"
        (list index-path
              (string-append root "/" doi-path)
              (string-append root "/" https-path))
        sources)
      (test-assert "the HTTP scheme does not affect snapshot lookup"
        (not (entity-metadata-ref snapshots "https://example.org/other")))
      (write-datum (string-append root "/" doi-path)
        `((uri . "doi:10.1234/wrong") (title . "mismatched")))
      (test-error "a snapshot cannot claim a different entity URI" #t
        (load-entity-metadata root))))
  (lambda ()
    (system* "rm" "-rf" root)))

(define failures (test-runner-fail-count (test-runner-current)))
(test-end "scheme-independent entity metadata snapshots")
(exit (if (zero? failures) 0 1))
