;;; SPDX-FileCopyrightText: 2026 Jinser Kafka <aimer@purejs.icu>
;;; SPDX-License-Identifier: GPL-3.0-or-later

(use-modules (ice-9 binary-ports)
             (ice-9 match)
             (ice-9 ftw)
             (srfi srfi-1)
             (srfi srfi-13)
             (web request)
             (web response)
             (web server)
             (web uri))

(define (reply code type body)
  (values (build-response #:code code
                          #:headers `((content-type . ,type)))
          body))

(define (safe-segment? segment)
  (and (not (member segment '("." "..")))
       (not (string-index segment #\/))
       (not (string-index segment #\\))
       (not (string-index segment #\nul))))

(define (regular-file? path)
  (and (file-exists? path)
       (eq? 'regular (stat:type (stat path)))))

(define (content-type path)
  (let* ((dot (string-rindex path #\.))
         (extension (and dot (string-downcase (substring path (+ dot 1))))))
    (cond ((member extension '("html" "htm")) '(text/html (charset . "utf-8")))
          ((equal? extension "css") '(text/css (charset . "utf-8")))
          ((member extension '("js" "mjs")) '(text/javascript (charset . "utf-8")))
          ((equal? extension "xml") '(application/xml (charset . "utf-8")))
          ((equal? extension "json") '(application/json (charset . "utf-8")))
          ((equal? extension "svg") '(image/svg+xml (charset . "utf-8")))
          ((equal? extension "png") '(image/png))
          ((member extension '("jpg" "jpeg")) '(image/jpeg))
          ((equal? extension "webp") '(image/webp))
          ((equal? extension "avif") '(image/avif))
          ((equal? extension "woff2") '(font/woff2))
          ((equal? extension "txt") '(text/plain (charset . "utf-8")))
          (else '(application/octet-stream)))))

(define (make-handler root)
  (let ((root-prefix (string-append root "/")))
    (define (inside-root? path)
      (or (string=? path root)
          (string-prefix? root-prefix path)))
    (define (lookup-file request)
      (let* ((parts (split-and-decode-uri-path
                     (uri-path (request-uri request))))
             (parts (if (null? parts) '("index.html") parts))
             (candidate (and (every safe-segment? parts)
                             (string-append root "/" (string-join parts "/")))))
        (and candidate
             (file-exists? candidate)
             (let ((resolved (canonicalize-path candidate)))
               (and (inside-root? resolved)
                    (regular-file? resolved)
                    resolved)))))
    (lambda (request body)
      (if (not (memq (request-method request) '(GET HEAD)))
          (reply 405 '(text/plain (charset . "utf-8")) "Method not allowed\n")
          (catch #t
            (lambda ()
              (let ((path (lookup-file request)))
                (if path
                    (reply 200 (content-type path)
                           (call-with-input-file path get-bytevector-all #:binary #t))
                    (reply 404 '(text/plain (charset . "utf-8")) "Not found\n"))))
            (lambda _
              (reply 400 '(text/plain (charset . "utf-8")) "Bad request\n")))))))

(define (main arguments)
  (match arguments
    ((host port root)
     (let ((port (string->number port))
           (root (canonicalize-path root)))
       (unless (and port (integer? port) (<= 1 port 65535))
         (error "preview port must be an integer from 1 to 65535" port))
       (unless (file-is-directory? root)
         (error "preview directory does not exist" root))
       (format #t "Serving ~a at http://~a:~a/\n" root host port)
       (force-output)
       (run-server (make-handler root) 'http
                   (list #:host host #:port port))))
    (_ (error "usage: guile scripts/preview.scm HOST PORT DIRECTORY"))))

(main (cdr (command-line)))
