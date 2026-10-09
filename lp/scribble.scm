;;; SPDX-License-Identifier: CC0-1.0
(define-module (lp scribble)
  #:use-module (lp core)
  #:use-module (language scribble source)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:export (code-fragment))

;; Whole definitions are retained as syntax values, without executing them.
;; Assembly deliberately gives them one fresh module namespace; this is not
;; hygienic insertion of arbitrary expression fragments into caller scopes.
(define-syntax code-fragment
  (lambda (stx)
    (define (expand id heading requires initial-requires forms)
      (let* ((definitions
               (filter (lambda (form)
                         (let ((datum (syntax->datum form)))
                           (not (and (string? datum)
                                     (string-null? (string-trim-both datum)))))) forms))
             (texts (map (lambda (form)
                           (let ((text (source-text (syntax-source form))))
                             (if (and text (string-prefix? "@" text))
                                 (substring text 1) text))) definitions)))
        (with-syntax ((id id) (heading heading)
                      ((definition ...) definitions)
                      (requires (datum->syntax stx (list 'quote requires)))
                      (initial-requires (datum->syntax stx (list 'quote initial-requires)))
                      (texts (datum->syntax stx (list 'quote texts)))
                      (origins (datum->syntax stx (list 'quote (map (lambda (form) (source-range (syntax-source form))) definitions)))))
          #'(make-fragment id heading
              (list #'definition ...) #:texts texts #:origins origins
              #:requires requires #:initial-requires initial-requires))))
    (syntax-case stx ()
      ((_ id heading #:requires (dependency ...) #:initial-requires (initial ...) form ...)
       (expand #'id #'heading (syntax->datum #'(dependency ...))
               (syntax->datum #'(initial ...)) #'(form ...)))
      ((_ id heading #:initial-requires (initial ...) form ...)
       (expand #'id #'heading '() (syntax->datum #'(initial ...)) #'(form ...)))
      ((_ id heading #:requires (dependency ...) form ...)
       (expand #'id #'heading (syntax->datum #'(dependency ...)) '() #'(form ...)))
      ((_ id heading form ...)
       (expand #'id #'heading '() '() #'(form ...))))))
