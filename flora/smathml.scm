;;; SPDX-FileCopyrightText: 2026 Jinser Kafka <aimer@purejs.icu>
;;; SPDX-License-Identifier: GPL-3.0-or-later

(define-module (flora smathml)
  #:use-module (grove ir)
  #:use-module (grove render rules)
  #:use-module (grove render context)
  #:use-module (ice-9 ftw)
  #:use-module (ice-9 popen)
  #:use-module (ice-9 rdelim)
  #:use-module (ice-9 regex)
  #:use-module (ice-9 textual-ports)
  #:use-module (sxml simple)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:export (smathml-source-files
            smathml-page
            make-smathml-page-render-rules))

;; This list is also the build graph: changing an imported Racket module
;; invalidates the Flora page which evaluates it.
(define-public smathml-source-files
  '("smathml_everything.rkt" "utils.rkt" "smathml0.rkt"
    "smathml1.rkt" "smathml_guide0.rkt" "proof-tree.rkt"
    "napier.rkt" "smathml_comments.rkt"))

;; SMathML emits links in its HTML, while Grove needs page IDs before render
;; time to build references and backmatter. Keep that route map here and mirror
;; each page's internal links as child `link` nodes in the authored IR. The
;; generated HTML is checked against this table during rendering.
(define smathml-html-routes
  '(("smathml0.html" "smathml-zh" "/smathml-zh.html")
    ("smathml1.html" "smathml-en" "/smathml-en.html")
    ("smathml_guide0.html" "smathml-guide" "/smathml-guide.html")
    ("proof_tree_test.html" "smathml-proof-tree" "/smathml-proof-tree.html")
    ("napier.html" "smathml-napier" "/smathml-napier.html")
    ("smathml_comments.html" "smathml-comments" "/smathml-comments.html")))

(define smathml-page-reference-files
  '(("smathml_everything.html"
     "smathml0.html" "smathml1.html" "smathml_guide0.html"
     "proof_tree_test.html" "napier.html" "smathml_comments.html")
    ("smathml1.html" "smathml0.html")
    ("smathml_guide0.html" "smathml0.html")))

(define (route-for-html-file file)
  (find (lambda (route) (string=? (car route) file))
        smathml-html-routes))

(define (page-reference-elements export)
  (let ((files (assoc export smathml-page-reference-files string=?)))
    (map
      (lambda (file)
        (let ((route (route-for-html-file file)))
          (unless route
            (error "SMathML reference has no Flora route" export file))
          (let ((target (cadr route)))
            (make-content-element 'link (list target)
              #:properties `((target . ,target))))))
      (if files (cdr files) '()))))

(define (valid-relative-source? source)
  (and (string? source)
       (not (string-null? source))
       (not (string-prefix? "/" source))
       (not (string-contains source ".."))))

(define-public (smathml-page source export)
  "Render an exported HTML value from a project-local Racket/SMathML module."
  (unless (valid-relative-source? source)
    (error "SMathML page source must be a relative path without .." source))
  (unless (and (string? export)
               (string-match "^[[:alpha:]_][[:alnum:]_.!?-]*$" export))
    (error "SMathML page export must be a Racket identifier" export))
  (make-content-element 'smathml-page (page-reference-elements export)
    #:properties `((source . ,source) (export . ,export))
    #:flow-kind 'block))

(define (racket-string value)
  ;; Scheme and Racket share the needed string literal escapes here.
  (call-with-output-string (lambda (port) (write value port))))

(define (run-page source-root source export)
  (let* ((path (canonicalize-path (string-append source-root "/" source)))
         (prefix (string-append (canonicalize-path source-root) "/")))
    (unless (string-prefix? prefix path)
      (error "SMathML page source escapes its source directory" source))
    (let ((directory (mkdtemp
                       (string-append (or (getenv "TMPDIR") "/tmp")
                                      "/flora-smathml-XXXXXX"))))
      (dynamic-wind
        (lambda () #t)
        (lambda ()
          (let ((script (string-append directory "/render.rkt")))
            (call-with-output-file script
              (lambda (port)
                (display "#lang racket\n(require SMathML/xml)\n" port)
                (format port "(Xml (dynamic-require (string->path ~a) '~a))\n"
                        (racket-string path) export)))
            (let* ((pipe (open-pipe* OPEN_READ "racket" script))
                   (html (get-string-all pipe))
                   (status (close-pipe pipe)))
              (unless (and (status:exit-val status)
                           (= 0 (status:exit-val status)))
                (error "Racket/SMathML page evaluation failed" source export status))
              (let ((raw (string-append directory "/page.html")))
                (call-with-output-file raw
                  (lambda (port) (display html port)))
                (let* ((pipe (open-pipe* OPEN_READ "python3"
                                         (string-append source-root
                                                        "/../normalize-html.py")
                                         raw))
                       (xml (get-string-all pipe))
                       (status (close-pipe pipe)))
                  (unless (and (status:exit-val status)
                               (= 0 (status:exit-val status)))
                    (error "could not normalize SMathML's HTML output" source status))
                  xml)))))
        (lambda ()
          (for-each
            (lambda (entry)
              (unless (member entry '("." ".."))
                (delete-file (string-append directory "/" entry))))
            (scandir directory))
          (rmdir directory))))))

(define (element? node)
  (and (pair? node) (symbol? (car node))))

(define (attributes node)
  (and (pair? (cdr node)) (pair? (cadr node))
       (eq? (caadr node) '@) (cdadr node)))

(define (children node)
  (if (attributes node) (cddr node) (cdr node)))

(define (find-element tree tag)
  (cond
    ((not (pair? tree)) #f)
    ((and (element? tree) (eq? (car tree) tag)) tree)
    (else
      (let search ((nodes tree))
        (and (pair? nodes)
             (or (find-element (car nodes) tag)
                 (search (cdr nodes))))))))

(define (rewrite-article node)
  (if (not (element? node))
      node
      (let* ((tag (car node))
             (attrs (attributes node))
             (body (map rewrite-article (children node)))
             (attrs (map rewrite-attribute (or attrs '())))
             (attrs (if (eq? tag 'math)
                        (if (assq 'xmlns attrs) attrs
                            (cons `(xmlns "http://www.w3.org/1998/Math/MathML")
                                  attrs))
                        attrs)))
        (cons tag (if attrs (cons `(@ ,@attrs) body) body)))))

(define (local-html-page-link? href)
  (and (string? href)
       (string-suffix? ".html" href)
       (not (string-contains href "://"))
       (not (string-prefix? "//" href))))

(define (html-hrefs tree)
  (cond
    ((element? tree)
     (append
       (let ((href (and (eq? (car tree) 'a)
                        (let ((entry (assq 'href (or (attributes tree) '()))))
                          (and entry (cadr entry))))))
         (if (string? href) (list href) '()))
       (append-map html-hrefs (children tree))))
    ((pair? tree) (append-map html-hrefs tree))
    (else '())))

(define (validate-page-references export body)
  (let* ((actual (filter local-html-page-link? (html-hrefs body)))
         (entry (assoc export smathml-page-reference-files string=?))
         (expected (if entry (cdr entry) '())))
    (unless (equal? actual expected)
      (error "SMathML page links differ from Grove's declared references"
             export expected actual))))

(define (rewrite-attribute attribute)
  (if (and (pair? attribute) (eq? (car attribute) 'href)
           (string? (cadr attribute))
           (string-suffix? ".html" (cadr attribute)))
      (let ((target (cadr attribute)))
        (let ((route (route-for-html-file target)))
          (if route
              `(href ,(caddr route))
              (if (local-html-page-link? target)
                  (error "SMathML page link has no Flora route" target)
                  attribute))))
      attribute))

(define (page-body document)
  (let* ((body (find-element document 'body))
         (content (if body (children body) '())))
    (unless body
      (error "SMathML module must export a complete HTML document"))
    ;; The original document title is represented by Flora's tree heading.
    (if (and (pair? content) (element? (car content))
             (eq? (caar content) 'h1))
        (cdr content)
        content)))

(define* (make-smathml-page-render-rules #:key source-root)
  "Render SMathML page nodes into Flora HTML using local Racket modules."
  (unless (and (string? source-root) (file-exists? source-root))
    (error "SMathML source root must be an existing directory" source-root))
  (make-render-rules
    (list
      (cons 'smathml-page
        (lambda (_context element _payload _next)
          (let* ((source (content-element-property element 'source))
                 (export (content-element-property element 'export))
                 (document (xml->sxml (run-page source-root source export)))
                 (body (page-body document)))
            (validate-page-references export body)
            `(div (@ (class "smathml-article"))
                  ,@(map rewrite-article body))))))))
