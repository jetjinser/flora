;;; SPDX-FileCopyrightText: 2026 Jinser Kafka <aimer@purejs.icu>
;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;

(use-modules (ice-9 ftw)
             (ice-9 textual-ports)
             (srfi srfi-13)
             (srfi srfi-64))

(define original-directory (getcwd))
(define test-root (mkdtemp "/tmp/flora-crossref-test-XXXXXX"))
(define test-bin (string-append test-root "/bin"))
(define test-metadata (string-append test-root "/metadata/entities"))
(define fixture-path (string-append test-root "/response.json"))
(define request-url-log (string-append test-root "/request-url"))
(define fake-curl (string-append test-bin "/curl"))
(define updater-path (canonicalize-path "scripts/update-crossref-metadata.scm"))
(define flora-modules (canonicalize-path "."))
(define grove-modules
  (canonicalize-path
   (dirname (dirname (search-path %load-path "grove/cache.scm")))))
(define original-path (getenv "PATH"))
(define uri "doi:10.1146/annurev.fluid.29.1.123")
(define unicode-uri "doi:10.1234/例")
(define complex-uri
  "doi:10.1002/(SICI)1521-3951(199911)216:1%3C135::AID-PSSB135%3E3.0.CO;2-%23")
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
    "output=\nwhile [ $# -gt 0 ]; do\n  case \"$1\" in https://*) printf '%s\\n' \"$1\" > \"$FLORA_CROSSREF_REQUEST_URL_LOG\";; esac\n  if [ \"$1\" = --output ]; then shift; output=$1; fi\n  shift\ndone\ncp \"$FLORA_CROSSREF_FIXTURE\" \"$output\""))

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
    (setenv "FLORA_CROSSREF_REQUEST_URL_LOG" request-url-log)
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
          index-bytes (read-text index-path))))
    (set! uri unicode-uri)
    (write-text fixture-path
      "{\"status\":\"ok\",\"message\":{\"DOI\":\"10.1234/例\",\"title\":[\"Unicode Crossref record\"]}}")
    (install-copying-curl)
    (test-assert "Unicode DOI refresh succeeds through Crossref" (zero? (run-updater)))
    (let ((snapshot (indexed-snapshot)))
      (test-equal "Crossref request URL percent-encodes Unicode"
        "https://api.crossref.org/works/10.1234/%E4%BE%8B"
        (string-trim-both (call-with-input-file request-url-log get-string-all)))
      (test-equal "Crossref snapshot retains authored Unicode IRI"
        unicode-uri (assoc-ref snapshot 'uri))
      (test-equal "Crossref provenance uses the encoded request URL"
        "https://api.crossref.org/works/10.1234/%E4%BE%8B"
        (assoc-ref snapshot 'source)))
    (set! uri complex-uri)
    (write-text fixture-path
      "{\"status\":\"ok\",\"message\":{\"DOI\":\"10.1002/(sici)1521-3951(199911)216:1<135::aid-pssb135>3.0.co;2-#\",\"title\":[\"Legacy SICI DOI\"]}}")
    (install-copying-curl)
    (test-assert "escaped legacy DOI matches Crossref's literal DOI field"
      (zero? (run-updater)))
    (let ((snapshot (indexed-snapshot)))
      (test-equal "Crossref API request keeps the documented escaped path"
        "https://api.crossref.org/works/10.1002/(SICI)1521-3951(199911)216:1%3C135::AID-PSSB135%3E3.0.CO;2-%23"
        (string-trim-both (call-with-input-file request-url-log get-string-all)))
      (test-equal "legacy DOI snapshot preserves the authored IRI"
        complex-uri (assoc-ref snapshot 'uri))))
  (lambda ()
    (chdir original-directory)
    (if original-path (setenv "PATH" original-path) (unsetenv "PATH"))
    (unsetenv "FLORA_CROSSREF_FIXTURE")
    (unsetenv "FLORA_CROSSREF_REQUEST_URL_LOG")
    (system* "rm" "-rf" test-root)))

(define failures (test-runner-fail-count (test-runner-current)))
(test-end "Flora Crossref metadata adapter")
(exit (if (zero? failures) 0 1))
