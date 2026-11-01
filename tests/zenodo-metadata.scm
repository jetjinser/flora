;;; SPDX-FileCopyrightText: 2026 Jinser Kafka <aimer@purejs.icu>
;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;
;;; Run from Flora's root inside its Guix environment:
;;;   guile --no-auto-compile tests/zenodo-metadata.scm

(use-modules (ice-9 ftw)
             (ice-9 textual-ports)
             (srfi srfi-1)
             (srfi srfi-64))

(define original-directory (getcwd))
(define test-root (mkdtemp "/tmp/flora-zenodo-test-XXXXXX"))
(define test-bin (string-append test-root "/bin"))
(define test-metadata (string-append test-root "/metadata/entities"))
(define fixture-path (string-append test-root "/response.json"))
(define temporary-path-log (string-append test-root "/temporary-path"))
(define fake-curl (string-append test-bin "/curl"))
(define updater-path (canonicalize-path "scripts/update-zenodo-metadata.scm"))
(define flora-modules (canonicalize-path "."))
(define grove-modules
  (canonicalize-path
   (dirname (dirname (search-path %load-path "grove/cache.scm")))))
(define original-path (getenv "PATH"))
(define uri "https://zenodo.org/records/12345")
(define other-uri "doi:10.1234/example")
(define other-path "metadata/entities/other.scm")

(define record
  "{\"doi\":\"10.5281/zenodo.12345\",\"metadata\":{\"title\":\"Test dataset\",\"description\":\"<p>A <em>small</em> dataset.</p>\",\"creators\":[{\"name\":\"Example, Ada\"},{\"name\":\"Research Group\"}],\"resource_type\":{\"type\":\"dataset\"},\"license\":{\"id\":\"cc-by-4.0\"}},\"links\":{\"self_html\":\"https://zenodo.org/records/12345\"}}")
(define changed-record
  "{\"doi\":\"10.5281/zenodo.12345\",\"metadata\":{\"title\":\"Changed dataset\",\"description\":\"<p>A <em>small</em> dataset.</p>\",\"creators\":[{\"name\":\"Example, Ada\"},{\"name\":\"Research Group\"}],\"resource_type\":{\"type\":\"dataset\"},\"license\":{\"id\":\"cc-by-4.0\"}},\"links\":{\"self_html\":\"https://zenodo.org/records/12345\"}}")
(define mismatched-record
  "{\"doi\":\"10.5281/zenodo.12345\",\"metadata\":{\"title\":\"Wrong record\",\"resource_type\":{\"type\":\"dataset\"}},\"links\":{\"self_html\":\"https://zenodo.org/records/99999\"}}")

(define (write-text path text)
  (call-with-output-file path (lambda (port) (display text port))))

(define (read-text path)
  (call-with-input-file path get-string-all))

(define (install-fake-curl body)
  (write-text fake-curl (string-append "#!/bin/sh\n" body "\n"))
  (chmod fake-curl #o755))

(define curl-arguments
  "output=\nwhile [ $# -gt 0 ]; do\n  if [ \"$1\" = --output ]; then shift; output=$1; fi\n  shift\ndone\nprintf '%s\\n' \"$output\" > \"$FLORA_ZENODO_TEMP_PATH_LOG\"\n")

(define (install-copying-curl)
  (install-fake-curl
    (string-append curl-arguments
                   "cp \"$FLORA_ZENODO_FIXTURE\" \"$output\"")))

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

(test-begin "Flora Zenodo metadata updater")
(dynamic-wind
  (lambda ()
    (mkdir test-bin)
    (mkdir (string-append test-root "/metadata"))
    (mkdir test-metadata)
    (write-text (string-append test-metadata "/index.scm")
      (format #f "((~s . ~s))~%" other-uri other-path))
    (write-text (string-append test-root "/" other-path)
      "((uri . \"doi:10.1234/example\") (title . \"Other\"))\n")
    (setenv "PATH" (string-append test-bin ":" original-path))
    (setenv "FLORA_ZENODO_FIXTURE" fixture-path)
    (setenv "FLORA_ZENODO_TEMP_PATH_LOG" temporary-path-log)
    (install-copying-curl)
    (write-text fixture-path record))
  (lambda ()
    (test-assert "Zenodo JSON becomes a dataset snapshot" (zero? (run-updater)))
    (let* ((snapshot (indexed-snapshot))
           (path (snapshot-path))
           (snapshot-bytes (read-text path))
           (index-path (string-append test-metadata "/index.scm"))
           (index-bytes (read-text index-path)))
      (test-equal "snapshot keeps its HTTPS landing-page identity" uri
        (assoc-ref snapshot 'uri))
      (test-equal "record type maps to dataset presentation" 'dataset
        (assoc-ref snapshot 'type))
      (test-equal "title, creators, and license are normalized"
        '("Test dataset" ("Example, Ada" "Research Group") "cc-by-4.0")
        (list (assoc-ref snapshot 'name)
              (assoc-ref snapshot 'creators)
              (assoc-ref snapshot 'license)))
      (test-equal "HTML description becomes plain text" "A small dataset."
        (assoc-ref snapshot 'description))
      (test-equal "DOI remains an external identifier" "10.5281/zenodo.12345"
        (assoc-ref snapshot 'doi))
      (test-assert "other URI schemes remain indexed"
        (find (lambda (entry) (string=? (car entry) other-uri))
              (call-with-input-file index-path read)))
      (test-assert "capture time is recorded" (assoc-ref snapshot 'captured-at))
      (test-assert "successful update removes temporary JSON"
        (not (file-exists? (last-response-file))))
      (system* "sleep" "2")
      (test-assert "identical metadata can be refreshed" (zero? (run-updater)))
      (test-equal "identical metadata leaves snapshot byte-stable"
        snapshot-bytes (read-text path))
      (test-equal "identical metadata leaves index byte-stable"
        index-bytes (read-text index-path))
      (write-text fixture-path changed-record)
      (test-assert "changed source data is accepted" (zero? (run-updater)))
      (test-equal "changed source data updates normalized snapshot"
        "Changed dataset" (assoc-ref (indexed-snapshot) 'name))
      (let ((updated-bytes (read-text path)))
        (install-failing-curl)
        (test-assert "network errors fail visibly" (not (zero? (run-updater))))
        (test-equal "network errors preserve prior snapshot"
          updated-bytes (read-text path))
        (test-assert "failed update removes temporary response"
          (not (file-exists? (last-response-file))))
        (install-copying-curl)
        (write-text fixture-path mismatched-record)
        (test-assert "a response for another landing page is rejected"
          (not (zero? (run-updater))))
        (test-equal "mismatched records preserve prior snapshot"
          updated-bytes (read-text path))
        (write-text fixture-path "{invalid JSON")
        (test-assert "malformed JSON is rejected" (not (zero? (run-updater))))
        (test-equal "malformed response preserves prior snapshot"
          updated-bytes (read-text path)))))
  (lambda ()
    (chdir original-directory)
    (if original-path (setenv "PATH" original-path) (unsetenv "PATH"))
    (unsetenv "FLORA_ZENODO_FIXTURE")
    (unsetenv "FLORA_ZENODO_TEMP_PATH_LOG")
    (system* "rm" "-rf" test-root)))

(define failures (+ (test-runner-fail-count (test-runner-current))
                    (test-runner-xpass-count (test-runner-current))))
(test-end "Flora Zenodo metadata updater")
(exit (if (zero? failures) 0 1))
