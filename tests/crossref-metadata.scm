;;; SPDX-FileCopyrightText: 2026 Jinser Kafka <aimer@purejs.icu>
;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;
;;; Run from Flora's root inside its Guix environment:
;;;   guile --no-auto-compile -L ../grove/modules -L . tests/crossref-metadata.scm

(use-modules (ice-9 ftw)
             (ice-9 textual-ports)
             (srfi srfi-13)
             (srfi srfi-64))

(define original-directory (getcwd))
(define test-root (mkdtemp "/tmp/flora-crossref-test-XXXXXX"))
(define test-bin (string-append test-root "/bin"))
(define test-metadata (string-append test-root "/metadata/entities"))
(define fixture-path (string-append test-root "/response.json"))
(define fake-curl (string-append test-bin "/curl"))
(define updater-path (canonicalize-path "scripts/update-crossref-metadata.scm"))
(define flora-modules (canonicalize-path "."))
(define grove-modules (canonicalize-path "../grove/modules"))
(define original-path (getenv "PATH"))
(define uri "doi:10.1146/annurev.fluid.29.1.123")
(define fixture
  "{\"status\":\"ok\",\"message\":{\"DOI\":\"10.1146/annurev.fluid.29.1.123\",\"type\":\"journal-article\",\"title\":[\"QUANTIFICATION OF UNCERTAINTY IN COMPUTATIONAL FLUID DYNAMICS\"],\"author\":[{\"given\":\"P. J.\",\"family\":\"Roache\"}],\"published-print\":{\"date-parts\":[[1997,1]]},\"container-title\":[\"Annual Review of Fluid Mechanics\"],\"publisher\":\"Annual Reviews\"}}")
(define mismatched-fixture
  "{\"status\":\"ok\",\"message\":{\"DOI\":\"10.1146/wrong\",\"title\":[\"Wrong record\"]}}")

(define (write-text path text)
  (call-with-output-file path (lambda (port) (display text port))))

(define (read-text path)
  (call-with-input-file path get-string-all))

(define (install-fake-curl body)
  (write-text fake-curl (string-append "#!/bin/sh\n" body "\n"))
  (chmod fake-curl #o755))

(define (install-copying-curl)
  (install-fake-curl
    "output=\nwhile [ $# -gt 0 ]; do\n  if [ \"$1\" = --output ]; then shift; output=$1; fi\n  shift\ndone\ncp \"$FLORA_CROSSREF_FIXTURE\" \"$output\""))

(define (run-updater)
  (chdir test-root)
  (let ((status
         (system* "guile" "--no-auto-compile"
                  "-L" grove-modules "-L" flora-modules updater-path uri)))
    (chdir original-directory)
    status))

(define (indexed-snapshot)
  (let* ((index (call-with-input-file
                    (string-append test-metadata "/index.scm") read))
         (entry (assoc uri index)))
    (and entry
         (call-with-input-file (string-append test-root "/" (cdr entry)) read))))

(test-begin "Flora Crossref metadata adapter")
(dynamic-wind
  (lambda ()
    (mkdir test-bin)
    (mkdir (string-append test-root "/metadata"))
    (mkdir test-metadata)
    (setenv "PATH" (string-append test-bin ":" original-path))
    (setenv "FLORA_CROSSREF_FIXTURE" fixture-path)
    (install-copying-curl)
    (write-text fixture-path fixture))
  (lambda ()
    (test-assert "Crossref response becomes a citation snapshot"
      (zero? (run-updater)))
    (let ((snapshot (indexed-snapshot)))
      (test-equal "Crossref record is normalized into the shared citation shape"
        '(citation
          "QUANTIFICATION OF UNCERTAINTY IN COMPUTATIONAL FLUID DYNAMICS"
          ("P. J. Roache") "1997" "Annual Review of Fluid Mechanics"
          "Annual Reviews")
        (list (assoc-ref snapshot 'type)
              (assoc-ref snapshot 'title)
              (assoc-ref snapshot 'authors)
              (assoc-ref snapshot 'year)
              (assoc-ref snapshot 'container-title)
              (assoc-ref snapshot 'publisher)))
      (test-equal "source provenance identifies Crossref"
        "https://api.crossref.org/works/10.1146/annurev.fluid.29.1.123"
        (assoc-ref snapshot 'source))
      (test-assert "storage adds capture time"
        (assoc-ref snapshot 'captured-at))
      (let* ((index-path (string-append test-metadata "/index.scm"))
             (snapshot-path
              (string-append test-root "/"
                (cdr (assoc uri (call-with-input-file index-path read)))))
             (snapshot-bytes (read-text snapshot-path))
             (index-bytes (read-text index-path)))
        (install-copying-curl)
        (write-text fixture-path mismatched-fixture)
        (test-assert "a different DOI response is rejected"
          (not (zero? (run-updater))))
        (test-equal "mismatched DOI leaves prior snapshot intact"
          snapshot-bytes (read-text snapshot-path))
        (test-equal "mismatched DOI leaves prior index intact"
          index-bytes (read-text index-path)))))
  (lambda ()
    (chdir original-directory)
    (if original-path (setenv "PATH" original-path) (unsetenv "PATH"))
    (unsetenv "FLORA_CROSSREF_FIXTURE")
    (system* "rm" "-rf" test-root)))

(define failures (test-runner-fail-count (test-runner-current)))
(test-end "Flora Crossref metadata adapter")
(exit (if (zero? failures) 0 1))
