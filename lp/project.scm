;;; SPDX-License-Identifier: CC0-1.0
(define-module (lp project)
  #:use-module (lp core)
  #:use-module (ice-9 pretty-print)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-9)
  #:use-module (srfi srfi-13)
  #:export (make-module-output module-output? module-output-name module-output-path
            module-output-program module-output-source
            make-project project? project-id project-heading project-outputs
            project-sources valid-output-path?
            instantiate-project project-instance? project-binding))

(define (safe-component? part)
  (and (string? part) (not (string-null? part))
       (char-set-contains? char-set:letter+digit (string-ref part 0))
       (string-every (lambda (c) (or (char<=? #\a c #\z) (char<=? #\0 c #\9)
                                   (char=? c #\-) (char=? c #\_))) part)))
(define (valid-output-path? path)
  (and (string? path) (string-suffix? ".scm" path)
       (every safe-component? (string-split (string-drop-right path 4) #\/))))

(define-record-type <module-output>
  (%make-module-output name path program) module-output?
  (name module-output-name) (path module-output-path) (program module-output-program))
(define (make-module-output name program)
  (unless (and (list? name) (pair? name) (every symbol? name) (program? program))
    (error "Module output requires a Guile module name and an LP program" name))
  (let ((path (string-append (string-join (map symbol->string name) "/") ".scm")))
    (unless (valid-output-path? path) (error "Unsafe LP module output path" name path))
    (%make-module-output name path program)))

(define (module-output-source output)
  (let ((program (module-output-program output)))
    (string-append
      ";;; Generated Guile module; edit the LP fragments.\n"
      (call-with-output-string
        (lambda (port)
          (pretty-print
            `(define-module ,(module-output-name output)
               ,@(append-map
                   (lambda (dependency)
                     (list #:use-module
                       `(,(import-module dependency) #:select ,(import-names dependency))))
                   (program-imports program))
               #:export ,(program-exports program)) port)))
      "\n" (program-source program #:include-imports? #f))))

(define-record-type <project>
  (%make-project id heading outputs) project?
  (id project-id) (heading project-heading) (outputs project-outputs))

(define (make-project id heading outputs)
  ;; Reuse the core's identity contract without evaluating any initializers.
  (unless (and (string? id) (safe-component? id) (string? heading)
               (not (string-null? heading)) (list? outputs) (pair? outputs)
               (every module-output? outputs))
    (error "Invalid LP project" id heading))
  (let ((paths (map module-output-path outputs))
        (ids (map (compose program-id module-output-program) outputs)))
    (unless (and (= (length paths) (length (delete-duplicates paths)))
                 (= (length ids) (length (delete-duplicates ids))))
      (error "Duplicate project module or program" id paths ids))
    (let ((available '()))
      (for-each
        (lambda (output)
          (let ((program (module-output-program output)))
            (for-each
              (lambda (dependency)
                (let ((provider
                       (find (lambda (candidate)
                               (equal? (module-output-name candidate) (import-module dependency))) outputs)))
                  (when provider
                    (unless (memq provider available)
                      (error "Project module must precede consumer (or forms a cycle)"
                             id (program-id program) (import-module dependency)))
                    (for-each
                      (lambda (name)
                        (unless (memq name (program-exports (module-output-program provider)))
                          (error "Project import is not exported by provider"
                                 id (program-id program) name
                                 (program-id (module-output-program provider)))))
                      (import-names dependency)))))
              (program-imports program)))
          (set! available (cons output available))) outputs)))
  (%make-project id heading outputs))

(define (project-sources project)
  (delete-duplicates
    (append-map (compose program-sources module-output-program) (project-outputs project))))

(define-record-type <project-instance>
  (%make-project-instance project modules) project-instance?
  (project instance-project) (modules instance-modules))

(define (instantiate-project project)
  (let ((modules '()))
    (for-each
      (lambda (output)
        (let ((instance
               (instantiate-program (module-output-program output)
                 #:resolve-import
                 (lambda (dependency)
                   (let ((internal (assoc-ref modules (import-module dependency))))
                     (if internal (instance-interface internal (import-names dependency))
                         (resolve-interface (import-module dependency)
                                            #:select (import-names dependency))))))))
          (set! modules (acons (module-output-name output) instance modules))))
      (project-outputs project))
    (%make-project-instance project modules)))

(define (project-binding instance module name)
  (let ((unit (assoc-ref (instance-modules instance) module)))
    (unless unit (error "Module is not part of LP project" module))
    (instance-binding unit name)))
