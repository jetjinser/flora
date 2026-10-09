;;; SPDX-License-Identifier: CC0-1.0
(define-module (lp forester)
  #:use-module (lp core)
  #:use-module (lp project)
  #:use-module (grove ir)
  #:use-module (grove style)
  #:use-module (grove style html)
  #:use-module (grove output)
  #:use-module (grove site)
  #:use-module ((forester site) #:select (pages))
  #:use-module ((forester commands) #:prefix f:)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:export (fragment-tree program-tree program-output source-output project-tree project-output
            program-check lp-enrich-site lp-artifacts))

(define (annotate element properties)
  (make-content-element (content-element-kind element) (content-element-children element)
    (content-element-source element)
    #:properties (append properties (content-element-properties element))
    #:style (content-element-style element) #:flow-kind (content-element-flow-kind element)))

(define (fragment-description fragment)
  `((id . ,(fragment-id fragment)) (heading . ,(fragment-heading fragment))
    (defines . ,(fragment-defines fragment)) (requires . ,(fragment-requires fragment))
    (initial-requires . ,(fragment-initial-requires fragment))))

(define (program-description program)
  `((id . ,(program-id program)) (heading . ,(program-heading program))
    (exports . ,(program-exports program))
    (imports . ,(map (lambda (dependency)
                      (cons (import-module dependency) (import-names dependency)))
                    (program-imports program)))
    (fragments . ,(map fragment-description (program-fragments program)))))

(define (label-paragraph label children)
  (make-content-element 'paragraph (cons label children)
    #:style (make-content-style 'literate-uses) #:flow-kind 'block))

(define* (fragment-tree fragment #:optional program)
  (when (and program (not (memq fragment (program-fragments program))))
    (error "Fragment is not part of program" (fragment-id fragment)))
  (annotate
    (f:subtree #:id (fragment-id fragment)
      (f:title (fragment-heading fragment)) (f:taxon "program")
      (make-content-element 'code-block (list (fragment-source fragment))
        #:properties '((language . scheme))
        #:style (make-content-style 'literate-code) #:flow-kind 'block))
    `((lp-fragment . ,(fragment-description fragment))
      ,@(if program `((lp-program-context . ,(program-description program))) '()))))

(define (source-output filename source sources)
  ;; Share the module exporter's relative-path contract.
  (unless (and (valid-output-path? filename) (string? source)
               (list? sources) (every string? sources))
    (error "LP output requires a safe relative .scm path, source and file dependencies" filename))
  (make-content-element 'paragraph
    (list "Download "
          (make-content-element 'span (list filename)
            #:style (make-content-style #f
              (list (make-html-tag "a")
                    (make-html-attributes `((href . ,(string-append "/programs/" filename))))))))
    #:properties `((literate-output . ,filename) (literate-source . ,source)
                   (literate-sources . ,(delete-duplicates sources)))
    #:flow-kind 'block))

(define (program-output filename program)
  (annotate (source-output filename (program-source program) (program-sources program))
    `((lp-output . ((path . ,filename) (program . ,(program-id program)))))))

(define (program-tree program)
  (annotate
    (f:subtree #:id (program-id program)
      (f:title (program-heading program)) (f:taxon "module")
      (label-paragraph "Exports: " (list (format #f "~s" (program-exports program))))
      (label-paragraph "Initialization order: "
        (list "片段按下列清单建立；函数体依赖可以相互引用。"))
      (make-content-element 'itemize
        (map (lambda (fragment)
               (make-content-element 'item
                 (list (f:link (fragment-id fragment) (fragment-heading fragment)))
                 #:flow-kind 'block))
             (program-fragments program)) #:flow-kind 'block))
    `((lp-program . ,(program-description program)))))

(define (project-tree project)
  (annotate
    (apply f:subtree #:id (project-id project)
      (append
        (list (f:title (project-heading project)) (f:taxon "project")
              (label-paragraph "Module order: "
                (list "文件按显式依赖顺序声明；每个Module拥有独立的导入和导出。")))
        (map (lambda (output) (program-tree (module-output-program output)))
             (project-outputs project))))
    `((lp-project . ,(map (lambda (output)
                           `((module . ,(module-output-name output))
                             (path . ,(module-output-path output))
                             (program . ,(program-id (module-output-program output)))
                             (project . ,(project-id project))))
                         (project-outputs project))))))

(define (project-output project)
  (make-content-element 'itemize
    (map (lambda (output)
           (make-content-element 'item
             (list (annotate
                     (source-output (module-output-path output) (module-output-source output)
                                    (project-sources project))
                     `((lp-output . ((path . ,(module-output-path output))
                                     (program . ,(program-id (module-output-program output))))))))
             #:flow-kind 'block))
         (project-outputs project)) #:flow-kind 'block))

(define (program-check programs example)
  ;; Associate an already checked tree with its subjects; this does not run it.
  (let ((plans (if (program? programs) (list programs) programs)))
    (unless (and (list? plans) (pair? plans) (every program? plans)
                 (content-element? example) (eq? (content-element-kind example) 'subtree)
                 (content-element-property example 'tree-id))
      (error "Program check requires plans and an addressed result tree"))
    (annotate example
      `((lp-check . ((id . ,(content-element-property example 'tree-id))
                     (heading . ,(content-element-property example 'title))
                     (programs . ,(map program-id plans))))))))

;; Descriptors contain only ordinary data, so Grove can cache the authored IR.
;; The index is rebuilt from that IR, never from a process-global registry.
(define (lp-enrich-site original)
  (define (collect node key)
    (append
      (if (and (content-element? node) (content-element-property node key))
          (list (content-element-property node key)) '())
      (append-map (lambda (child) (collect child key))
        (cond ((content-document? node) (content-document-children node))
              ((content-element? node) (content-element-children node))
              (else '())))))
  (define (entries key)
    (append-map (lambda (page) (collect (site-page-document page) key)) (site-pages original)))
  (define plans (delete-duplicates (append (entries 'lp-program) (entries 'lp-program-context))
                                  (lambda (a b) (equal? (assq-ref a 'id) (assq-ref b 'id)))))
  (define files (delete-duplicates (append (entries 'lp-output) (append-map identity (entries 'lp-project)))))
  (define checks (delete-duplicates (entries 'lp-check)))
  (define (separated items)
    (if (null? items) '() (cons (car items) (append-map (lambda (x) (list ", " x)) (cdr items)))))
  (define (plan-link plan) (f:link (assq-ref plan 'id) (assq-ref plan 'heading)))
  (define (download path)
    (make-content-element 'span (list path)
      #:style (make-content-style #f
        (list (make-html-tag "a") (make-html-attributes `((href . ,(string-append "/programs/" path))))))))
  (define (output-links ids)
    (delete-duplicates
      (filter-map (lambda (file) (and (member (assq-ref file 'program) ids) (assq-ref file 'path))) files)))
  (define (providers plan name)
    (append
      (filter (lambda (fragment) (memq name (assq-ref fragment 'defines)))
              (assq-ref plan 'fragments))
      (append-map
        (lambda (dependency)
          (let* ((file (and (memq name (cdr dependency))
                           (find (lambda (file) (equal? (assq-ref file 'module) (car dependency))) files)))
                 (provider (and file (find (lambda (candidate)
                                            (equal? (assq-ref candidate 'id) (assq-ref file 'program))) plans))))
            (if provider
                (filter (lambda (fragment) (memq name (assq-ref fragment 'defines)))
                        (assq-ref provider 'fragments)) '())))
        (assq-ref plan 'imports))))
  (define (fragment-nav descriptor)
    (let* ((id (assq-ref descriptor 'id))
           (users (filter (lambda (plan)
                            (any (lambda (fragment) (equal? id (assq-ref fragment 'id)))
                                 (assq-ref plan 'fragments))) plans))
           (paths (output-links (map (lambda (plan) (assq-ref plan 'id)) users))))
      (append
        (list (label-paragraph "Defines: " (list (format #f "~s" (assq-ref descriptor 'defines)))))
        (if (null? users) '() (list (label-paragraph "Assembled in " (separated (map plan-link users)))))
        (if (null? paths) '() (list (label-paragraph "Outputs: " (separated (map download paths)))))
        (append-map
          (lambda (key label)
            (let ((names (assq-ref descriptor key)))
              (if (null? names) '()
                  (list (label-paragraph label
                    (separated
                      (map (lambda (name)
                             (let ((definitions
                                    (delete-duplicates
                                      (append-map
                                        (lambda (plan) (providers plan name)) users))))
                               (cond ((null? definitions) (symbol->string name))
                                     ((null? (cdr definitions))
                                      (f:link (assq-ref (car definitions) 'id) (symbol->string name)))
                                     (else
                                      (make-content-element 'span
                                        (separated (map (lambda (definition)
                                                          (f:link (assq-ref definition 'id)
                                                            (format #f "~a [~a]" name (assq-ref definition 'id))))
                                                        definitions))))))) names)))))))
          '(requires initial-requires) '("Requires: " "Initial requires: ")))))
  (define (program-nav descriptor)
    (let ((paths (output-links (list (assq-ref descriptor 'id))))
          (results (filter (lambda (check)
                             (member (assq-ref descriptor 'id) (assq-ref check 'programs))) checks)))
      (append
        (if (null? paths) '() (list (label-paragraph "Outputs: " (separated (map download paths)))))
        (if (null? results) '()
            (list (label-paragraph "Checks: "
                    (separated (map (lambda (check)
                                      (f:link (assq-ref check 'id) (assq-ref check 'heading))) results)))))
        (map
          (lambda (dependency)
            (let ((provider (find (lambda (file) (equal? (assq-ref file 'module) (car dependency))) files)))
              (label-paragraph "Imports: "
                (list (if provider
                          (f:link (assq-ref provider 'program) (format #f "~s" (car dependency)))
                          (format #f "~s" (car dependency)))
                      " " (format #f "~s" (cdr dependency))))))
          (assq-ref descriptor 'imports)))))
  (define (walk node)
    (cond
      ((content-document? node)
       (make-content-document (map walk (content-document-children node)) (content-document-source node)))
      ((content-element? node)
       (let* ((fragment (content-element-property node 'lp-fragment))
              (program (content-element-property node 'lp-program))
              (children (map walk (content-element-children node)))
              (nav (cond (fragment (fragment-nav fragment)) (program (program-nav program)) (else '())))
              ;; Frontmatter retains its leading position; add navigation before
              ;; the code/list body, not as a separate numbered subtree.
              (front (take-while (lambda (child)
                                   (and (content-element? child)
                                        (memq (content-element-kind child) '(title taxon)))) children)))
         (make-content-element (content-element-kind node)
           (append front nav (drop children (length front))) (content-element-source node)
           #:properties (content-element-properties node) #:style (content-element-style node)
           #:flow-kind (content-element-flow-kind node))))
      (else node)))
  (make-site
    (map (lambda (page)
           (make-site-page (site-page-id page) (site-page-title page)
             (walk (site-page-document page)) (site-page-source page)
             #:metadata (site-page-metadata page))) (site-pages original))
    #:title (site-title original) #:description (site-description original) #:sources (site-sources original)))

(define (lp-artifacts forest)
  (define (outputs content source)
    (cond
      ((content-document? content)
       (append-map (lambda (child) (outputs child source))
                   (content-document-children content)))
      ((content-element? content)
       (let ((filename (content-element-property content 'literate-output)))
         (if filename
             (list (make-artifact (string-append "programs/" filename)
                     (or (content-element-property content 'literate-source)
                         (content-verbatim-string (content-element-children content)))
                     (delete-duplicates (cons source
                       (or (content-element-property content 'literate-sources) '())))))
             (append-map (lambda (child) (outputs child source))
                         (content-element-children content)))))
      (else '())))
  ;; Use authored roots, because Forester also exposes extracted subtrees.
  (append-map (lambda (page)
                (if (assq-ref (site-page-metadata page) 'inline-subtree) '()
                    (outputs (site-page-document page) (site-page-source page))))
              (pages forest)))
