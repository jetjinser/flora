;;; SPDX-FileCopyrightText: 2026 Jinser Kafka <aimer@purejs.icu>
;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;
;;; Run from Flora's root:
;;;   guile --no-auto-compile -L ../grove/modules -L . tests/entity-snapshot.scm

(use-modules (flora entity-snapshot)
             (ice-9 ftw)
             (ice-9 textual-ports)
             (srfi srfi-11)
             (srfi srfi-64))

(define root (mkdtemp "/tmp/flora-entity-snapshot-XXXXXX"))
(define uri "https://example.test/entities/1")
(define other-uri "doi:10.1234/another")
(define initial
  `((uri . ,uri) (type . dataset) (name . "Example") (source . "fixture")))
(define changed
  `((uri . ,uri) (type . dataset) (name . "Changed") (source . "fixture")))

(define (snapshot-path)
  (let* ((index (call-with-input-file
                    (string-append root "/metadata/entities/index.scm") read))
         (entry (assoc uri index)))
    (and entry (string-append root "/" (cdr entry)))))

(define (read-bytes path)
  (call-with-input-file path get-string-all))

(test-begin "shared entity snapshot storage")
(dynamic-wind
  (lambda () #t)
  (lambda ()
    (let-values (((status path) (store-entity-snapshot! root uri initial)))
      (test-eq "first capture writes a snapshot" 'updated status)
      (test-equal "index path resolves to the stored snapshot"
        path (snapshot-path))
      (let* ((stored (call-with-input-file path read))
             (bytes (read-bytes path)))
        (test-equal "stored record preserves source fields" initial
          (filter (lambda (field) (not (eq? (car field) 'captured-at))) stored))
        (test-assert "storage adds a capture timestamp"
          (assoc-ref stored 'captured-at))
        (let-values (((unchanged-status unchanged-path)
                      (store-entity-snapshot! root uri initial)))
          (test-eq "identical data reuses its snapshot" 'unchanged unchanged-status)
          (test-equal "identical data keeps the same path" path unchanged-path)
          (test-equal "identical data leaves bytes and capture time stable"
            bytes (read-bytes path)))
        (let-values (((changed-status changed-path)
                      (store-entity-snapshot! root uri changed)))
          (test-eq "changed data replaces snapshot contents" 'updated changed-status)
          (test-equal "changed data keeps its URI-derived path" path changed-path)
          (test-equal "changed fields are persisted" "Changed"
            (assoc-ref (call-with-input-file path read) 'name)))
        (let-values (((other-status other-path)
                      (store-entity-snapshot!
                        root other-uri
                        `((uri . ,other-uri) (type . citation)))))
          (test-eq "another URI is added" 'updated other-status)
          (test-assert "updating an entity preserves other index entries"
            (assoc other-uri
              (call-with-input-file
                (string-append root "/metadata/entities/index.scm") read))))))
    (test-error "a source cannot store data under another URI" #t
      (store-entity-snapshot! root uri '((uri . "https://example.test/wrong")))))
  (lambda () (system* "rm" "-rf" root)))

(define failures (test-runner-fail-count (test-runner-current)))
(test-end "shared entity snapshot storage")
(exit (if (zero? failures) 0 1))
