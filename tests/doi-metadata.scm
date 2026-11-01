;;; SPDX-FileCopyrightText: 2026 Jinser Kafka <aimer@purejs.icu>
;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;
;;; Run from Flora's root inside its Guix environment:
;;;   guile --no-auto-compile -L ../grove/modules tests/doi-metadata.scm

(use-modules (ice-9 ftw)
             (ice-9 textual-ports)
             (flora private doi)
             (srfi srfi-1)
             (srfi srfi-13)
             (srfi srfi-64))

(define original-directory (getcwd))
(define test-root (mkdtemp "/tmp/flora-doi-test-XXXXXX"))
(define test-bin (string-append test-root "/bin"))
(define test-metadata (string-append test-root "/metadata/entities"))
(define fixture-path (string-append test-root "/response.json"))
(define temporary-path-log (string-append test-root "/temporary-path"))
(define request-url-log (string-append test-root "/request-url"))
(define fake-curl (string-append test-bin "/curl"))
(define updater-path (canonicalize-path "scripts/update-doi-metadata.scm"))
(define flora-modules (canonicalize-path "."))
(define grove-modules
  (canonicalize-path
   (dirname (dirname (search-path %load-path "grove/cache.scm")))))
(define original-path (getenv "PATH"))
(define uri "doi:10.1234/grove-test")
(define unicode-uri "doi:10.1234/例")
(define https-uri "https://example.org/publication/42")
(define https-snapshot-path "metadata/entities/https-fixture.scm")

(define vector-record
  "{\"DOI\":\"10.1234/grove-test\",\"title\":[\"A test record\"],\"author\":[{\"given\":\"Ada\",\"family\":\"Lovelace\"},{\"name\":\"Research Group\"}],\"issued\":{\"date-parts\":[[2020,2,3]]},\"container-title\":[\"Test Journal\"],\"publisher\":\"Test Press\"}")
(define changed-record
  "{\"DOI\":\"10.1234/grove-test\",\"title\":[\"A changed test record\"],\"author\":[{\"given\":\"Ada\",\"family\":\"Lovelace\"},{\"name\":\"Research Group\"}],\"issued\":{\"date-parts\":[[2020,2,3]]},\"container-title\":[\"Test Journal\"],\"publisher\":\"Test Press\"}")
(define scalar-record
  "{\"DOI\":\"10.1234/grove-test\",\"title\":\"A scalar CSL title\",\"author\":[{\"name\":\"Data Curation Consortium\"}],\"issued\":{\"date-parts\":[[2018]]},\"container-title\":\"Zenodo\",\"publisher\":\"DataCite\"}")
(define mismatched-record
  "{\"DOI\":\"10.1234/wrong\",\"title\":[\"A mismatched record\"]}")

(define (write-text path text)
  (call-with-output-file path (lambda (port) (display text port))))

(define (read-text path)
  (call-with-input-file path get-string-all))

(define (install-fake-curl body)
  (write-text fake-curl (string-append "#!/bin/sh\n" body "\n"))
  (chmod fake-curl #o755))

(define curl-arguments
  "output=\nwhile [ $# -gt 0 ]; do\n  case \"$1\" in https://*) printf '%s\\n' \"$1\" > \"$FLORA_DOI_REQUEST_URL_LOG\";; esac\n  if [ \"$1\" = --output ]; then shift; output=$1; fi\n  shift\ndone\nprintf '%s\\n' \"$output\" > \"$FLORA_DOI_TEMP_PATH_LOG\"\n")

(define (install-copying-curl)
  (install-fake-curl
    (string-append curl-arguments
                   "cp \"$FLORA_DOI_FIXTURE\" \"$output\"")))

(define (install-failing-curl)
  (install-fake-curl (string-append curl-arguments "exit 22")))

(define (run-updater)
  (chdir test-root)
  (let ((status
         (system* "guile" "--no-auto-compile"
                  "-L" grove-modules "-L" flora-modules updater-path uri)))
    (chdir original-directory)
    status))

(define (snapshot-path)
  (let* ((index (call-with-input-file
                    (string-append test-metadata "/index.scm") read))
         (entry (assoc uri index)))
    (and entry (string-append test-root "/" (cdr entry)))))

(define (indexed-snapshot)
  (let ((path (snapshot-path)))
    (and path (call-with-input-file path read))))

(define (last-response-file)
  (and (file-exists? temporary-path-log)
       (string-trim-both (read-text temporary-path-log))))

(test-begin "Flora DOI metadata updater")
(dynamic-wind
  (lambda ()
    (mkdir test-bin)
    (mkdir (string-append test-root "/metadata"))
    (mkdir test-metadata)
    (write-text (string-append test-metadata "/index.scm")
      (format #f "((~s . ~s))~%" https-uri https-snapshot-path))
    (write-text (string-append test-root "/" https-snapshot-path)
      (format #f "((uri . ~s) (source . \"fixture\") (title . \"HTTPS record\"))~%"
              https-uri))
    (setenv "PATH" (string-append test-bin ":" original-path))
    (setenv "FLORA_DOI_FIXTURE" fixture-path)
    (setenv "FLORA_DOI_TEMP_PATH_LOG" temporary-path-log)
    (setenv "FLORA_DOI_REQUEST_URL_LOG" request-url-log)
    (install-copying-curl)
    (write-text fixture-path vector-record)
    (test-equal "Unicode DOI IRI yields its authored DOI name"
      "10.1234/例" (doi-iri-name unicode-uri))
    (test-equal "escaped reserved path characters remain escaped"
      "https://doi.org/10.1234/a%3Fb"
      (doi-request-url "https://doi.org/"
        (doi-iri-name "doi:10.1234/a%3Fb")))
    (test-equal "raw query syntax is not accepted as part of a DOI name"
      #f (doi-iri-name "doi:10.1234/a?b"))
    (test-assert "DOI comparison folds ASCII only"
      (doi-iri-name-matches? "10.1234/ABC例" "10.1234/abc例"))
    (test-assert "DOI comparison does not fold Unicode letters"
      (not (doi-iri-name-matches? "10.1234/Ä" "10.1234/ä")))
    (test-assert "percent-encoded DOI punctuation matches literal API data"
      (doi-iri-name-matches?
        "10.1002/(SICI)1521-3951(199911)216:1%3C135::AID-PSSB135%3E3.0.CO;2-%23"
        "10.1002/(sici)1521-3951(199911)216:1<135::aid-pssb135>3.0.co;2-#"))
    (test-assert "percent-encoded UTF-8 matches a literal Unicode DOI"
      (doi-iri-name-matches? "10.1234/%E4%BE%8B" "10.1234/例"))
    (write-text fixture-path
      "{\"DOI\":\"10.1234/例\",\"title\":[\"Unicode DOI record\"]}")
    (set! uri unicode-uri))
  (lambda ()
    (test-assert "Unicode DOI refresh succeeds offline" (zero? (run-updater)))
    (test-equal "Unicode DOI is UTF-8 percent-encoded for HTTP"
      "https://doi.org/10.1234/%E4%BE%8B"
      (string-trim-both (read-text request-url-log)))
    (test-equal "Unicode request preserves authored IRI in snapshot"
      unicode-uri (assoc-ref (indexed-snapshot) 'uri))
    (set! uri "doi:10.1234/grove-test")
    (write-text fixture-path vector-record)
    (test-assert "vector CSL fixture produces a snapshot" (zero? (run-updater)))
    (let* ((snapshot (indexed-snapshot))
           (path (snapshot-path))
           (snapshot-bytes (read-text path))
           (index-path (string-append test-metadata "/index.scm"))
           (index-bytes (read-text index-path)))
      (test-equal "snapshot retains the requested URI" uri (assoc-ref snapshot 'uri))
      (test-equal "DOI snapshots declare their presentation kind" 'citation
        (assoc-ref snapshot 'type))
      (test-equal "snapshot captures the CSL title" "A test record"
        (assoc-ref snapshot 'title))
      (test-equal "personal and organizational authors are retained"
        '("Ada Lovelace" "Research Group") (assoc-ref snapshot 'authors))
      (test-assert "DOI refresh preserves other-scheme snapshot entries"
        (assoc https-uri
          (call-with-input-file index-path read)
          string=?))
      (test-assert "snapshot records when its content was captured"
        (assoc-ref snapshot 'captured-at))
      (test-assert "successful update removes its temporary response"
        (not (file-exists? (last-response-file))))
      (system* "sleep" "2")
      (test-assert "re-fetching identical metadata succeeds" (zero? (run-updater)))
      (test-equal "identical metadata leaves the snapshot byte-for-byte stable"
        snapshot-bytes (read-text path))
      (test-equal "identical metadata leaves the index stable"
        index-bytes (read-text index-path))
      (write-text fixture-path changed-record)
      (system* "sleep" "2")
      (test-assert "changed metadata is accepted" (zero? (run-updater)))
      (let* ((updated (indexed-snapshot))
             (updated-bytes (read-text path)))
        (test-equal "changed metadata updates the title"
          "A changed test record" (assoc-ref updated 'title))
        (test-assert "changed metadata replaces the snapshot"
          (not (string=? snapshot-bytes updated-bytes)))
        (write-text fixture-path scalar-record)
        (test-assert "scalar CSL fields are accepted" (zero? (run-updater)))
        (let* ((scalar (indexed-snapshot))
               (scalar-bytes (read-text path))
               (scalar-index (read-text index-path)))
          (test-equal "scalar title is retained" "A scalar CSL title"
            (assoc-ref scalar 'title))
          (test-equal "scalar container title is retained" "Zenodo"
            (assoc-ref scalar 'container-title))
          (test-equal "organization author name is retained"
            '("Data Curation Consortium") (assoc-ref scalar 'authors))
          (install-failing-curl)
          (test-assert "a failed request exits unsuccessfully"
            (not (zero? (run-updater))))
          (test-equal "a failed request preserves the prior snapshot"
            scalar-bytes (read-text path))
          (test-equal "a failed request preserves the prior index"
            scalar-index (read-text index-path))
          (test-assert "failed request removes its temporary response"
            (not (file-exists? (last-response-file))))
          (install-copying-curl)
          (write-text fixture-path mismatched-record)
          (test-assert "a DOI-mismatched response is rejected"
            (not (zero? (run-updater))))
          (test-equal "a mismatched response preserves the prior snapshot"
            scalar-bytes (read-text path))
          (test-equal "a mismatched response preserves the prior index"
            scalar-index (read-text index-path))
          (test-assert "mismatched response removes its temporary file"
            (not (file-exists? (last-response-file))))
          (install-copying-curl)
          (write-text fixture-path "{not valid JSON")
          (test-assert "malformed CSL-JSON is rejected"
            (not (zero? (run-updater))))
          (test-equal "malformed JSON preserves the prior snapshot"
            scalar-bytes (read-text path))
          (test-equal "malformed JSON preserves the prior index"
            scalar-index (read-text index-path))
          (test-assert "malformed response removes its temporary file"
            (not (file-exists? (last-response-file))))))))
  (lambda ()
    (chdir original-directory)
    (if original-path (setenv "PATH" original-path) (unsetenv "PATH"))
    (unsetenv "FLORA_DOI_FIXTURE")
    (unsetenv "FLORA_DOI_TEMP_PATH_LOG")
    (unsetenv "FLORA_DOI_REQUEST_URL_LOG")
    (system* "rm" "-rf" test-root)))

(define failures (+ (test-runner-fail-count (test-runner-current))
                    (test-runner-xpass-count (test-runner-current))))
(test-end "Flora DOI metadata updater")
(exit (if (zero? failures) 0 1))
