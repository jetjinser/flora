;;; SPDX-FileCopyrightText: 2026 Jinser Kafka <aimer@purejs.icu>
;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;
;;; Run from Flora's root inside its Guix environment:
;;;   guile --no-auto-compile -L ../grove/modules tests/doi-metadata.scm

(use-modules (ice-9 ftw)
             (ice-9 textual-ports)
             (srfi srfi-1)
             (srfi srfi-64))

(define original-directory (getcwd))
(define test-root (mkdtemp "/tmp/flora-doi-test-XXXXXX"))
(define test-bin (string-append test-root "/bin"))
(define test-metadata (string-append test-root "/metadata/dois"))
(define fixture-path (string-append test-root "/response.json"))
(define fake-curl (string-append test-bin "/curl"))
(define updater-path (canonicalize-path "scripts/update-doi-metadata.scm"))
(define grove-modules (canonicalize-path "../grove/modules"))
(define original-path (getenv "PATH"))
(define uri "doi:10.1234/grove-test")

(define valid-record
  "{\"DOI\":\"10.1234/grove-test\",\"title\":[\"A test record\"],\"author\":[{\"given\":\"Ada\",\"family\":\"Lovelace\"},{\"name\":\"Research Group\"}],\"issued\":{\"date-parts\":[[2020,2,3]]},\"container-title\":[\"Test Journal\"],\"publisher\":\"Test Press\"}")
(define changed-record
  "{\"DOI\":\"10.1234/grove-test\",\"title\":[\"A changed test record\"],\"author\":[{\"given\":\"Ada\",\"family\":\"Lovelace\"},{\"name\":\"Research Group\"}],\"issued\":{\"date-parts\":[[2020,2,3]]},\"container-title\":[\"Test Journal\"],\"publisher\":\"Test Press\"}")
(define mismatched-record
  "{\"DOI\":\"10.1234/wrong\",\"title\":[\"A mismatched record\"]}")

(define (write-text path text)
  (call-with-output-file path (lambda (port) (display text port))))

(define (read-text path)
  (call-with-input-file path get-string-all))

(define (install-fake-curl body)
  (write-text fake-curl (string-append "#!/bin/sh\n" body "\n"))
  (chmod fake-curl #o755))

(define (install-copying-curl)
  (install-fake-curl
    "output=\nwhile [ $# -gt 0 ]; do\n  if [ \"$1\" = --output ]; then shift; output=$1; fi\n  shift\ndone\ncp \"$FLORA_DOI_FIXTURE\" \"$output\""))

(define (run-updater)
  (chdir test-root)
  (let ((status
         (system* "guile" "--no-auto-compile"
                  "-L" grove-modules updater-path uri)))
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

(test-begin "Flora DOI metadata updater")
(dynamic-wind
  (lambda ()
    (mkdir test-bin)
    (mkdir (string-append test-root "/metadata"))
    (mkdir test-metadata)
    (setenv "PATH" (string-append test-bin ":" original-path))
    (setenv "FLORA_DOI_FIXTURE" fixture-path)
    (install-copying-curl)
    (write-text fixture-path valid-record))
  (lambda ()
    (test-assert "valid fixture produces a snapshot" (zero? (run-updater)))
    (let* ((snapshot (indexed-snapshot))
           (path (snapshot-path))
           (snapshot-bytes (read-text path))
           (index-path (string-append test-metadata "/index.scm"))
           (index-bytes (read-text index-path)))
      (test-equal "snapshot retains the requested URI" uri (assoc-ref snapshot 'uri))
      (test-equal "snapshot captures the CSL title" "A test record"
        (assoc-ref snapshot 'title))
      (test-equal "personal and organizational authors are retained"
        '("Ada Lovelace" "Research Group") (assoc-ref snapshot 'authors))
      (test-assert "snapshot records when its content was captured"
        (assoc-ref snapshot 'captured-at))
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
             (updated-bytes (read-text path))
             (updated-index (read-text index-path)))
        (test-equal "changed metadata updates the title"
          "A changed test record" (assoc-ref updated 'title))
        (test-assert "changed metadata replaces the snapshot"
          (not (string=? snapshot-bytes updated-bytes)))
        (install-fake-curl "exit 22")
        (test-assert "a failed request exits unsuccessfully"
          (not (zero? (run-updater))))
        (test-equal "a failed request preserves the prior snapshot"
          updated-bytes (read-text path))
        (test-equal "a failed request preserves the prior index"
          updated-index (read-text index-path))
        (install-copying-curl)
        (write-text fixture-path mismatched-record)
        (test-assert "a DOI-mismatched response is rejected"
          (not (zero? (run-updater))))
        (test-equal "a mismatched response preserves the prior snapshot"
          updated-bytes (read-text path))
        (test-equal "a mismatched response preserves the prior index"
          updated-index (read-text index-path)))))
  (lambda ()
    (chdir original-directory)
    (if original-path (setenv "PATH" original-path) (unsetenv "PATH"))
    (unsetenv "FLORA_DOI_FIXTURE")
    (system* "rm" "-rf" test-root)))

(define failures (+ (test-runner-fail-count (test-runner-current))
                    (test-runner-xpass-count (test-runner-current))))
(test-end "Flora DOI metadata updater")
(exit (if (zero? failures) 0 1))
