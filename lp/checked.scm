;;; SPDX-License-Identifier: CC0-1.0
(define-module (lp checked)
  #:use-module (lp check)
  #:use-module (grove ir)
  #:use-module (grove style)
  #:use-module (language scribble source)
  #:use-module ((forester commands) #:prefix f:)
  #:use-module (ice-9 pretty-print)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:export (program checked-example checked-property checked-error))

(define (program-tree id heading forms texts)
  (let ((source (string-join
                  (map (lambda (form text)
                         (or text
                             (call-with-output-string
                               (lambda (port) (pretty-print form port)))))
                       forms texts)
                  "\n\n")))
    (f:subtree #:id id
      (f:title heading) (f:taxon "program")
      (make-content-element 'code-block (list source)
        #:properties '((language . scheme))
        #:style (make-content-style 'literate-code) #:flow-kind 'block))))

;; Keep the caller syntax intact; capture source while its range context is active.
(define-syntax program
  (lambda (stx)
    (syntax-case stx ()
      ((_ id heading form ...)
       (let* ((definitions
                (filter (lambda (form)
                          (let ((datum (syntax->datum form)))
                            (not (and (string? datum)
                                      (string-null? (string-trim-both datum))))))
                        #'(form ...)))
              (texts (map (lambda (form)
                            (let ((text (source-text (syntax-source form))))
                              ;; The display is Scheme; omit only the at-exp escape.
                              (if (and text (string-prefix? "@" text))
                                  (substring text 1) text))) definitions)))
         (with-syntax (((definition ...) definitions)
                       (texts (datum->syntax stx (list 'quote texts))))
           #'(begin definition ...
                    (program-tree id heading '(definition ...) texts))))))))

(define (syntax-origin stx)
  (let ((origin (syntax-source stx)))
    (and origin
         `((file . ,(assq-ref origin 'filename))
           (line . ,(+ 1 (or (assq-ref origin 'line) 0)))
           (column . ,(+ 1 (or (assq-ref origin 'column) 0)))))))

(define (source-label location)
  (if (and location (assq-ref location 'file))
      (format #f "~a:~a:~a" (assq-ref location 'file)
              (assq-ref location 'line) (assq-ref location 'column))
      "<unknown source>"))

(define* (example-tree id heading expression actual expected #:optional location source)
  (check-equal id actual expected #:origin location)
  (f:subtree #:id id
    (f:title heading) (f:taxon "example")
    (make-content-element 'code-block
      (list (or source (call-with-output-string (lambda (port) (pretty-print expression port)))))
      #:properties '((language . scheme))
      #:style (make-content-style 'literate-code) #:flow-kind 'block)
    (make-content-element 'paragraph
      (list "⇒ " (make-content-element 'code
                    (list (format #f "~s" actual))) " · checked")
      #:style (make-content-style 'literate-result) #:flow-kind 'block)))

(define-syntax checked-example
  (lambda (stx)
    (syntax-case stx ()
      ((_ id heading expression expected)
       (with-syntax ((location (datum->syntax stx (list 'quote (syntax-origin stx))))
                     (source (datum->syntax stx (source-text (syntax-source #'expression)))))
         #'(example-tree id heading 'expression expression expected location source))))))

(define (property-tree id heading expression samples predicate location)
  (let* ((count (check-samples id samples predicate #:origin location))
         (result (format #f "~a cases passed" count)))
    (example-tree id heading expression result result)))

(define-syntax checked-property
  (lambda (stx)
    (syntax-case stx ()
      ((_ id heading samples predicate)
       (with-syntax ((location (datum->syntax stx (list 'quote (syntax-origin stx)))))
         #'(property-tree id heading 'predicate samples predicate location))))))

(define (error-tree id heading expression thunk expected-key)
  (check-error id thunk expected-key)
  (let ((result (format #f "expected exception: ~a" expected-key)))
    (example-tree id heading expression result result)))

(define-syntax checked-error
  (syntax-rules ()
    ((_ id heading expression expected-key)
     (error-tree id heading 'expression (lambda () expression) expected-key))))

