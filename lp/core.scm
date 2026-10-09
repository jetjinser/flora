;;; SPDX-License-Identifier: CC0-1.0
(define-module (lp core)
  #:use-module (ice-9 pretty-print)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-9)
  #:use-module (srfi srfi-13)
  #:export (make-fragment fragment? fragment-id fragment-heading fragment-origin
            fragment-requires fragment-initial-requires fragment-defines fragment-datums fragment-source
            make-import import? import-module import-names
            make-program program? program-id program-heading program-fragments
            program-exports program-imports program-datums program-source program-sources
            instantiate-program instance? instance-program instance-binding instance-interface))

(define (validate-identity id heading)
  (unless (and (string? id) (not (string-null? id))
               (string-every (lambda (c) (or (char<=? #\a c #\z)
                                           (char<=? #\0 c #\9) (char=? c #\-))) id)
               (string? heading) (not (string-null? heading)))
    (error "LP requires a short ASCII identity and a heading" id heading)))

(define-record-type <program-fragment>
  (%make-program-fragment id heading forms texts origins requires initial-requires)
  fragment?
  (id fragment-id)
  (heading fragment-heading)
  (forms fragment-forms)
  (texts fragment-texts)
  (origins fragment-origins)
  (requires fragment-requires)
  (initial-requires fragment-initial-requires))

(define (fragment-origin fragment)
  (find identity (fragment-origins fragment)))

(define* (make-fragment id heading forms #:key
                        (texts (map (lambda (_) #f) forms))
                        (origins (map (lambda (_) #f) forms))
                        (requires '()) (initial-requires '()))
  (validate-identity id heading)
  (unless (and (pair? forms) (= (length forms) (length texts) (length origins))
               (list? requires) (every symbol? requires)
               (list? initial-requires) (every symbol? initial-requires))
    (error "Invalid program fragment" id))
  (%make-program-fragment id heading forms texts origins
    (delete-duplicates requires) (delete-duplicates initial-requires)))

(define (fragment-datums fragment)
  (map syntax->datum (fragment-forms fragment)))

(define (fragment-source fragment)
  (string-join
    (map (lambda (form text)
           (or text (call-with-output-string
                      (lambda (port) (pretty-print (syntax->datum form) port)))))
         (fragment-forms fragment) (fragment-texts fragment))
    (string #\newline #\newline)))

(define (fragment-definition-name form id)
  (let ((datum (syntax->datum form)))
    (unless (and (pair? datum) (eq? (car datum) 'define)
                 (pair? (cdr datum)))
      (error "Fragment requires whole define forms" id datum))
    (let* ((head (cadr datum)) (name (if (pair? head) (car head) head)))
      (unless (symbol? name) (error "Invalid fragment definition" id datum))
      name)))


(define (fragment-defines fragment)
  (map (lambda (form) (fragment-definition-name form (fragment-id fragment)))
       (fragment-forms fragment)))

(define-record-type <import>
  (%make-import module names) import?
  (module import-module) (names import-names))

(define (make-import module names)
  (unless (and (list? module) (pair? module) (every symbol? module)
               (list? names) (pair? names) (every symbol? names)
               (= (length names) (length (delete-duplicates names))))
    (error "LP import requires a module and unique selected names" module names))
  (%make-import module names))

(define-record-type <program>
  (%make-program id heading fragments exports imports)
  program?
  (id program-id) (heading program-heading)
  (fragments program-fragments) (exports program-exports) (imports program-imports))

(define-record-type <instance>
  (%make-instance program module)
  instance?
  (program instance-program) (module instance-module))

(define* (make-program id heading fragments exports #:key (imports '()))
  (validate-identity id heading)
  (unless (and (list? fragments) (pair? fragments) (every fragment? fragments)
               (list? exports) (every symbol? exports)
               (list? imports) (every import? imports))
    (error "Invalid program assembly" id))
  (let* ((ids (map fragment-id fragments))
         (names (append-map fragment-defines fragments))
         (imported (append-map import-names imports))
         (default-module (make-fresh-user-module)))
    (unless (= (length ids) (length (delete-duplicates ids)))
      (error "Duplicate fragment in assembly" id ids))
    (let ((owners '()))
      (for-each
        (lambda (fragment)
          (for-each
            (lambda (name)
              (let ((previous (assq name owners)))
                (when previous
                  (error "Duplicate definition in assembly" id name
                         (fragment-id (cdr previous)) (fragment-origin (cdr previous))
                         (fragment-id fragment) (fragment-origin fragment)))
                (set! owners (acons name fragment owners))))
            (fragment-defines fragment))) fragments))
    (unless (= (length (append names imported))
               (length (delete-duplicates (append names imported))))
      (error "Conflicting local or imported bindings" id names imported))
    (unless (and (= (length exports) (length (delete-duplicates exports)))
                 (every (lambda (name) (memq name names)) exports))
      (error "Unknown or duplicate assembly export" id exports))
    (let ((available imported))
      (for-each
        (lambda (fragment)
          (for-each
            (lambda (name)
              (unless (or (memq name names) (memq name imported)
                          (module-defined? default-module name))
                (error "Missing fragment dependency" id (fragment-id fragment)
                       name (fragment-origin fragment))))
            (fragment-requires fragment))
          ;; Initial requirements are explicit fragment-level barriers, not a
          ;; static analysis of Scheme evaluation or an automatic sort.
          (for-each
            (lambda (name)
              (unless (or (memq name available)
                          (and (not (memq name names))
                               (module-defined? default-module name)))
                (error "Initialization dependency must precede fragment" id
                       (fragment-id fragment) name (fragment-origin fragment))))
            (fragment-initial-requires fragment))
          (set! available (append (fragment-defines fragment) available)))
        fragments))
    (%make-program id heading fragments exports imports)))

(define* (instantiate-program program #:key
                              (resolve-import (lambda (dependency)
                                                (resolve-interface (import-module dependency)
                                                  #:select (import-names dependency)))))
  (unless (program? program) (error "Expected an LP program" program))
  (let ((module (make-fresh-user-module)))
    (for-each
      (lambda (dependency)
        (catch #t
          (lambda ()
            (module-use! module (resolve-import dependency)))
          (lambda (key . arguments)
            (error "Program import failed" (program-id program)
                   (import-module dependency) (import-names dependency) key arguments))))
      (program-imports program))
    (for-each
      (lambda (fragment)
        (for-each
          (lambda (form origin)
            (catch #t
              (lambda ()
                (let ((datum (syntax->datum form)))
                  (set-source-properties! datum
                    (if origin
                        `((filename . ,(assq-ref origin 'file))
                          (line . ,(- (assq-ref origin 'line) 1))
                          (column . ,(- (assq-ref origin 'column) 1))) '()))
                  (eval datum module)))
              (lambda (key . arguments)
                (error "Program instantiation failed" (program-id program)
                       (fragment-id fragment) origin key arguments))))
          (fragment-forms fragment) (fragment-origins fragment)))
      (program-fragments program))
    (%make-instance program module)))

(define (instance-binding instance name)
  (unless (instance? instance) (error "Expected an LP instance" instance))
  (unless (memq name (program-exports (instance-program instance)))
    (error "Binding is not exported" (program-id (instance-program instance)) name))
  (module-ref (instance-module instance) name))

(define (instance-interface instance names)
  (let ((interface (make-module)))
    (for-each (lambda (name)
                (unless (memq name (program-exports (instance-program instance)))
                  (error "Binding is not exported" (program-id (instance-program instance)) name))
                (module-add! interface name (module-variable (instance-module instance) name))) names)
    interface))

(define (program-datums program)
  (append-map fragment-datums (program-fragments program)))

(define (program-sources program)
  (delete-duplicates
    (filter-map (lambda (fragment)
                  (let ((origin (fragment-origin fragment)))
                    (and origin (assq-ref origin 'file))))
                (program-fragments program))))

(define* (program-source program #:key (include-imports? #t))
  (string-append
    ";;; Generated from an LP program; edit the fragment sources.\n"
    ";;; Execution order follows the declared program.\n\n"
    (if (or (not include-imports?) (null? (program-imports program))) ""
        (string-append
          (call-with-output-string
            (lambda (port)
              (pretty-print
                `(use-modules ,@(map (lambda (dependency)
                                      `(,(import-module dependency) #:select ,(import-names dependency)))
                                    (program-imports program))) port))) "\n"))
    (string-join
      (map (lambda (fragment)
             (let ((origin (fragment-origin fragment)))
               (string-append ";;; " (fragment-id fragment) " — "
                 (if origin
                     (format #f "~a:~a" (basename (assq-ref origin 'file))
                             (assq-ref origin 'line)) "unknown source")
                 "\n" (fragment-source fragment))))
           (program-fragments program)) "\n\n") "\n"))
