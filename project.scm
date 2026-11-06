;;; Flora project description.

;; Load the project-local LP library through Guile's normal module loader.
(eval-when (expand load eval)
  (let ((project-root (dirname (current-filename))))
    (unless (member project-root %load-path)
      (set! %load-path (cons project-root %load-path)))))

(use-modules (cjk-fonts)
             (flora)
             (flora entity-metadata)
             (flora entity-presentation)
             (flora figure-assets)
             (flora smathml)
             (flora temml)
             (ice-9 ftw)
             (ice-9 binary-ports)
             (ice-9 textual-ports)
             (forester style html)
             (grove style html)
             (grove output)
             (forester input scribble)
             (forester render html)
             (forester render rss)
             (forester render sitemap)
             (forester render site)
             (forester project new)
             (forester style i18n)
             (grove input scribble)
             (grove project)
             (grove project site)
             (grove render)
             (grove render html presentation)
             (grove render html routes)
             (grove i18n)
             (forester site)
             (grove site)
             (grove ir)
             (system base language)
             (language scribble spec)
             (lp forester)
             (grove render html)
             (grove render html image)
             (grove render rules)
             (srfi srfi-1)
             (srfi srfi-13))

(define (project-directory% subdir)
  (string-append (dirname (current-filename)) subdir))
(define output-directory (project-directory% "/build"))
(define plant-directory (project-directory% "/plants"))
(define literate-module-sources
  (map (lambda (name) (string-append plant-directory "/" name))
       '("lib/commands.plant" "lib/queries.plant"
         "lp-0003.plant" "lp-0008.plant" "lp-0007.plant"
         "lp-0009.plant")))
(define read-flora-document
  (make-scribble-document-reader))
(define (flora-page-environment)
  (let ((environment (default-environment scribble)))
    ;; These are project defaults for Flora pages. Keep @use-commands available
    ;; for documents that need a different or additional command set.
    (module-use! environment (resolve-interface '(flora)))
    (for-each
      (lambda (name)
        (module-use! environment (resolve-interface name)))
      command-modules)
    environment))
(define read-flora-page
  (make-scribble-document-reader #:environment-factory flora-page-environment))
(define-values (prepare-literate read-flora-module-page)
  (make-scribble-module-session literate-module-sources
    #:read-document read-flora-document))
(define (read-flora-page-document path)
  (if (member (canonicalize-path path)
              (map canonicalize-path literate-module-sources)
              string=?)
      (read-flora-module-page path)
      (read-flora-page path)))
(define (prepare-flora)
  (prepare-literate))

(define stylesheet-path (project-directory% "/style.css"))
(define feed-stylesheet-path (project-directory% "/feed.css"))
(define theme-script-path (project-directory% "/theme.js"))
(define temml-directory
  (let* ((search-path (getenv "TEMML_PACKAGE"))
         (directory
          (and search-path
               (find (lambda (path)
                       (file-exists?
                        (string-append path "/dist/Temml-Local.css")))
                     (string-split search-path #\:)))))
    (unless directory
      (error "Temml is unavailable; activate Flora's Guix environment"))
    directory))
(define temml-stylesheet-path
  (string-append temml-directory "/dist/Temml-Local.css"))
(define temml-font-path
  (string-append temml-directory "/dist/Temml.woff2"))
(define temml-worker-path (project-directory% "/scripts/temml-worker.cjs"))
(define font-directory (project-directory% "/fonts"))
(define font-sources
  (map (lambda (name) (string-append font-directory "/" name))
       (scandir font-directory (lambda (name) (not (string-prefix? "." name))))))
(define flora-module-sources
  (map project-directory%
       (list "/flora/entity-metadata.scm"
             "/flora/entity-presentation.scm"
             "/flora/figure-assets.scm"
             "/flora/smathml.scm"
             "/flora/temml.scm")))
(define smathml-sources
  (append
    (map (lambda (name) (project-directory% (string-append "/smathml/source/" name)))
         smathml-source-files)
    (map project-directory%
         '("/smathml/normalize-html.py"
           "/smathml/manifest.scm"
           "/channels.scm"))))
(define entity-metadata-sources
  (entity-metadata-source-paths (dirname (current-filename))))
(define entity-metadata
  (load-entity-metadata (dirname (current-filename))))
(define font-assets
  (map (lambda (path)
         (make-byte-artifact (string-append "fonts/" (basename path))
           (call-with-input-file path get-bytevector-all #:binary #t)
           #:sources (list path)))
       font-sources))

(define-values (blazek2005-figure-pipelines figure-image-sets)
  (make-blazek2005-figure-assets (dirname (current-filename))))
(define flora-rules
  (compose-render-rules
    (make-render-rules
      (list (cons 'image (image-set-rule figure-image-sets))))
    (make-smathml-page-render-rules
      #:source-root (project-directory% "/smathml/source"))
    (make-temml-html-rules temml-worker-path)))
(define flora-style
  (compose-html-styles
    default-html-style
    default-bilingual-style
    (make-html-style
      #:stylesheets
      (list (make-artifact "flora.css"
              (call-with-input-file stylesheet-path get-string-all)
              #:sources (list stylesheet-path))
            (make-artifact "temml.css"
              (call-with-input-file temml-stylesheet-path get-string-all)
              #:sources (list temml-stylesheet-path)))
      #:assets
      (append
        (list (make-artifact "theme.js"
                (call-with-input-file theme-script-path get-string-all)
                #:sources (list theme-script-path))
              (make-artifact "feed.css"
                (call-with-input-file feed-stylesheet-path get-string-all)
                #:sources (list feed-stylesheet-path)))
        (list (make-byte-artifact "Temml.woff2"
                (call-with-input-file temml-font-path get-bytevector-all
                  #:binary #t)
                #:sources (list temml-font-path)))
        font-assets))))

(define html-routes (make-html-routes #:home-page "flora"))

(define flora-locale "zh-Hans")
(define flora-messages
  (make-message-catalog
    '(("zh-Hans" . ((backmatter-context . "语境")
                    (backmatter-references . "参考文献")
                    (backmatter-backlinks . "反向链接")
                    (backmatter-related . "相关")
                    (describes . "描述的实体"))))
    #:default flora-locale))
(define flora-settings
  (make-site-settings #:site-url "https://flora.purejs.icu"
                      #:default-locale flora-locale))

;; Interface strings rendered outside the trees: backmatter labels and the
;; theme controls. The font subset must carry their glyphs even though no
;; tree happens to contain them.
(define interface-text
  (string-append "语境参考文献反向链接相关描述的实体"
                 "回到首页"
                 "站点配色设置跟随系统配色使用日间配色使用夜间配色"
                 "跳到正文站点导航目录将树作为页面打开更新于年月日外部元数据"
                 "外部文献：外部数据集：许可："
                 (string-concatenate
                   (append-map
                     (lambda (entry)
                       (let ((metadata (cdr entry)))
                         (append (filter string?
                                 (list (assq-ref metadata 'title)
                                       (assq-ref metadata 'name)
                                       (assq-ref metadata 'description)
                                       (assq-ref metadata 'license)
                                       (assq-ref metadata 'landing-page)))
                                 (or (assq-ref metadata 'authors) '())
                                 (filter string?
                                         (list (assq-ref metadata 'year)
                                               (assq-ref metadata
                                                         'container-title))))))
                     entity-metadata))))

;; Flora composes Grove's HTML presentation values: document head,
;; route-aware site navigation, per-page title decoration, the reading-column
;; article wrapper, and collapsible backmatter.
(define (taxon-entry-sxml taxon)
  ;; Render the tree's own taxon element with Flora's markup; the
  ;; element comes straight from Grove's page-taxon accessor, so only
  ;; this tree's frontmatter can appear - never a nested tree's.
  (list `(span (@ (class "taxon")
                   (data-taxon ,(content-element-property taxon 'id)))
                ,@(map content->sxml (content-element-children taxon))
                ". ")))

(define flora-head
  (list '(meta (@ (name "viewport")
                  (content "width=device-width, initial-scale=1")))
        '(link (@ (rel "alternate") (type "application/rss+xml")
                  (title "Flora") (href "/feed.xml")))
        '(script (@ (src "/theme.js")) "")))

(define theme-controls-sxml
  '(div (@ (class "theme-controls") (hidden "hidden")
           (role "group") (aria-label "站点配色设置"))
     (div (@ (class "theme-options"))
       (label (input (@ (type "radio") (name "flora-theme") (value "system")
                        (aria-label "跟随系统配色")))
              (span "Auto"))
       (label (input (@ (type "radio") (name "flora-theme") (value "light")
                        (aria-label "使用日间配色")))
              (span "Day"))
       (label (input (@ (type "radio") (name "flora-theme") (value "dark")
                        (aria-label "使用夜间配色")))
              (span "Night")))))

(define (flora-title-decoration forest page-id)
  (let ((taxon (page-taxon (require-page forest page-id))))
    (if taxon (taxon-entry-sxml taxon) '())))

(define (flora-reference-metadata-items forest page-id)
  (or (let find ((uris (or (assq-ref
                             (site-page-metadata (require-page forest page-id))
                             'describes)
                           '())))
        (and (pair? uris)
             (let ((metadata (entity-metadata-ref entity-metadata (car uris))))
               (if metadata
                   (let ((item (entity-metadata-item metadata)))
                     (if item (list item) (find (cdr uris))))
                   (find (cdr uris))))))
      '()))

(define render-flora
  (make-html-renderer
    #:rules-id (string-append "flora-html-rules-v2:" temml-directory)
    #:options
    (make-html-options
      #:routes html-routes
      #:mathjax-src #f
      #:settings flora-settings
      #:messages flora-messages
      #:presentation
      (compose-html-presentations
        (make-html-presentation #:style flora-style #:rules flora-rules)
        (make-html-presentation
          #:head flora-head
          #:title-decorations flora-title-decoration
          #:home-link
          (make-html-home-link
            '((span (@ (class "home-icon") (aria-hidden "true")) "«")
              "Flora")
            #:attributes '((title . "回到首页")))
          #:site-nav (list theme-controls-sxml)
          #:metadata-items flora-reference-metadata-items
          #:page-sources (lambda (_forest _page-id) entity-metadata-sources)
          #:cache-id 'flora-page-presentation-v1))
      #:article? #t
      #:backmatter-details? #t
      ;; 边注在渲染期抬入页面级 lane:锚点留编号上标,注释按文档序
      ;; 收进 .margin-lane,各带回链——不再依赖 theme.js 搬运 DOM。
      #:side-lane '(flora-sidenote))))

(define (analyze-flora site)
  ((module-ref (resolve-interface '(flora queries)) 'analyze-flora) (lp-enrich-site site)))

(define flora-project
  (make-site-project
    #:title "Flora"
    #:description "A garden of connected notes."
    #:source-directory plant-directory
    #:extra-sources (append (list stylesheet-path feed-stylesheet-path
                                  theme-script-path temml-stylesheet-path
                                  temml-font-path temml-worker-path)
                            font-sources flora-module-sources smathml-sources
                            entity-metadata-sources)
    #:prepare prepare-flora
    #:read-page (make-page-reader read-flora-page-document)
    #:analyze analyze-flora
    #:reader-locale flora-locale
    #:renderers
    (list render-flora lp-artifacts
          (make-cjk-font-renderer
            (project-directory% "/fonts-src")
            #:extra-text interface-text)
          (make-sitemap-renderer
            #:settings flora-settings #:routes html-routes)
          (make-rss-renderer
            #:settings flora-settings #:routes html-routes
            #:stylesheet-url "feed.css"
            #:stylesheet-type "text/css"))
    #:pipelines blazek2005-figure-pipelines
    #:create-source
    (make-forester-source-creator
      #:source-directory plant-directory
      #:template
      (lambda (id date)
        (string-append
          "@title{}\n"
          "@published{" date "}\n")))
    #:output-directory output-directory))

flora-project
