;;; SPDX-FileCopyrightText: 2026 Jinser Kafka <aimer@purejs.icu>
;;;
;;; SPDX-License-Identifier: GPL-3.0-or-later

(define-module (flora temml)
  #:use-module (grove ir)
  #:use-module (grove render rules)
  #:use-module (ice-9 popen)
  #:use-module (ice-9 rdelim)
  #:use-module (ice-9 textual-ports)
  #:use-module (language scribble command)
  #:use-module (rnrs bytevectors)
  #:use-module (sxml simple)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:export (make-temml-html-rules))

(define hex-digits "0123456789abcdef")
(define mathml-namespace "http://www.w3.org/1998/Math/MathML")

(define (string->hex text)
  (let ((bytes (string->utf8 text)))
    (string-concatenate
      (map (lambda (index)
             (let ((byte (bytevector-u8-ref bytes index)))
               (string (string-ref hex-digits (quotient byte 16))
                       (string-ref hex-digits (modulo byte 16)))))
           (iota (bytevector-length bytes))))))

(define (make-temml-html-rules worker)
  "Return HTML rules that render TeX math nodes as MathML with Temml.

WORKER is the project-controlled Node worker script. A single bidirectional
process serves all formulas in the site render, avoiding one Node startup per
formula. The Node process exits when the build closes its input pipe."
  (unless (and (string? worker) (file-exists? worker))
    (error "Temml worker script does not exist" worker))
  (let ((port #f))
    (define (start-worker)
      (or port
          (begin
            (set! port (open-pipe* OPEN_BOTH "node" worker))
            port)))
    (define (render-tex element)
      (let* ((display? (content-element-property element 'display?))
             (number (content-element-property element 'number))
             (source (content-verbatim-string
                       (content-element-children element)))
             (source (if number
                         (string-append source " \\tag{" number "}")
                         source))
             (worker-port (start-worker)))
        (display (if display? "d\t" "i\t") worker-port)
        (display (string->hex source) worker-port)
        (newline worker-port)
        (force-output worker-port)
        (let ((response (read-line worker-port)))
          (when (eof-object? response)
            (error "Temml worker exited before returning MathML"))
          (if (string-prefix? "ERR\t" response)
              (error "Temml could not render TeX" (substring response 4))
              (unless (string-prefix? "OK\t" response)
                (error "invalid Temml worker response" response)))
          (let* ((parsed (xml->sxml (substring response 3)))
                 (root (and (pair? parsed) (pair? (cdr parsed))
                            (cadr parsed))))
            (unless (and (pair? root) (symbol? (car root)))
              (error "Temml did not return a MathML root" parsed))
            (let ((mathml (normalize-mathml root)))
              (unless (eq? (car mathml) 'math)
                (error "Temml did not return a MathML root" mathml))
              mathml)))))
    (define (normalize-mathml node)
      (let* ((name (symbol->string (car node)))
             (prefix (string-append mathml-namespace ":"))
             (tag (if (string-prefix? prefix name)
                      (string->symbol (substring name (string-length prefix)))
                      (car node)))
             (has-attributes? (and (pair? (cdr node))
                                   (pair? (cadr node))
                                   (eq? (caadr node) '@)))
             (attributes (if has-attributes? (cdadr node) '()))
             (children (if has-attributes? (cddr node) (cdr node))))
        (cons tag
          (cons (cons '@
                  (if (eq? tag 'math)
                      (cons `(xmlns ,mathml-namespace) attributes)
                      attributes))
                (map (lambda (child)
                       (if (and (pair? child) (symbol? (car child)))
                           (normalize-mathml child)
                           child))
                     children)))))
    (define (replace-fallback-body fallback body)
      (unless (and (pair? fallback) (symbol? (car fallback)))
        (error "expected default math wrapper from HTML renderer" fallback))
      (let* ((has-attributes? (and (pair? (cdr fallback))
                                   (pair? (cadr fallback))
                                   (eq? (caadr fallback) '@)))
             (prefix (if has-attributes? (take fallback 2) (take fallback 1))))
        (append prefix (list body))))
    (make-render-rules
      (list
        (cons 'math
          (lambda (_context element fallback next)
            (if (content-element-property element 'tex?)
                (replace-fallback-body fallback (render-tex element))
                (next))))))))
