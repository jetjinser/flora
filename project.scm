;;; Flora project description.

;; Load the project-local LP library through Guile's normal module loader.
(set! %load-path (cons (dirname (current-filename)) %load-path))

(use-modules (cjk-fonts)
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
             (forester style i18n)
             (grove input scribble)
             (grove project)
             (grove project site)
             (grove render html routes)
             (forester site)
             (grove site)
             (grove ir)
             (lp forester)
             (grove render html)
             (srfi srfi-1)
             (srfi srfi-13))

(define (project-directory% subdir)
  (string-append (dirname (current-filename)) subdir))
(define output-directory (project-directory% "/build"))
(define plant-directory (project-directory% "/plants"))
(define literate-module-sources
  (map (lambda (name) (string-append plant-directory "/" name))
       '("lib/commands.plant" "lib/queries.plant" "lib/literate.plant"
         "lp-0003.plant" "lp-0008.plant" "lp-0007.plant"
         "lp-0009.plant")))
(define read-flora-document
  (make-scribble-document-reader))
(define-values (prepare-literate read-flora-page-document)
  (make-scribble-module-session literate-module-sources
    #:read-document read-flora-document))
(define (prepare-flora)
  (prepare-literate))

(define stylesheet-path (project-directory% "/style.css"))
(define feed-stylesheet-path (project-directory% "/feed.css"))
(define theme-script-path (project-directory% "/theme.js"))
(define font-directory (project-directory% "/fonts"))
(define font-sources
  (map (lambda (name) (string-append font-directory "/" name))
       (scandir font-directory (lambda (name) (not (string-prefix? "." name))))))
(define font-assets
  (map (lambda (path)
         (make-byte-artifact (string-append "fonts/" (basename path))
           (call-with-input-file path get-bytevector-all #:binary #t)
           (list path)))
       font-sources))

;; 图片资产:assets/ 下按目录结构注册(如 assets/blazek2005/fig-2-1.png → URL /blazek2005/fig-2-1.png),
;; 供 @image 引用。子目录递归,隐藏文件跳过。
(define asset-directory (project-directory% "/assets"))
(define (asset-files dir)
  (append-map
    (lambda (name)
      (let ((path (string-append dir "/" name)))
        (if (eq? (stat:type (stat path)) 'directory)
            (map (lambda (n) (string-append name "/" n))
                 (asset-files path))
            (list name))))
    (scandir dir (lambda (name) (not (string-prefix? "." name))))))
(define image-assets
  (map (lambda (rel)
         (make-byte-artifact rel
           (call-with-input-file (string-append asset-directory "/" rel)
             get-bytevector-all #:binary #t)
           (list (string-append asset-directory "/" rel))))
       (asset-files asset-directory)))
(define flora-style
  (compose-html-styles
    default-html-style
    default-bilingual-style
    (make-html-style
      #:stylesheets
      (list (make-artifact "flora.css"
              (call-with-input-file stylesheet-path get-string-all)
              (list stylesheet-path)))
      #:assets
      (append
        (list (make-artifact "theme.js"
                (call-with-input-file theme-script-path get-string-all)
                (list theme-script-path))
              (make-artifact "feed.css"
                (call-with-input-file feed-stylesheet-path get-string-all)
                (list feed-stylesheet-path)))
        font-assets
        image-assets))))

(define html-routes (make-html-routes #:home-page "flora"))
;; Interface strings rendered outside the trees: backmatter labels and the
;; theme controls. The font subset must carry their glyphs even though no
;; tree happens to contain them.
(define interface-text
  (string-append "语境参考文献反向链接相关"
                 "回到首页"
                 "站点配色设置跟随系统配色使用日间配色使用夜间配色"))
(define flora-sitemap
  (make-sitemap-renderer
    #:site-url "https://flora.purejs.icu"
    #:routes html-routes))
(define flora-rss
  (make-rss-renderer
    #:site-url "https://flora.purejs.icu"
    #:routes html-routes
    #:stylesheet-url "feed.css"
    #:stylesheet-type "text/css"))

;; Flora's presentation is composed from Grove's HTML hooks instead of
;; rewriting rendered markup: document attributes and head nodes, the site
;; navigation, per-tree title decoration, the reading-column article wrapper,
;; and collapsible backmatter.
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
        ;; MathJax 配置必须先于 tex-chtml.js 加载。displayOverflow=scale:超宽展示公式
        ;; 按比例缩放而非横向滚动;pageReady 钩子在排版完成后补一次锚点滚动——
        ;; 否则浏览器先按未排版的短文本定位,MathJax 渲染后锚点会漂移出视口。
        '(script (@ (type "text/javascript"))
          "window.MathJax = { output: { displayOverflow: 'scale' }, startup: { pageReady: function () { return MathJax.startup.defaultPageReady().then(function () { var h = decodeURIComponent(location.hash.slice(1)); if (h) { var el = document.getElementById(h); if (el) el.scrollIntoView(); } }); } } };")
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

(define (flora-home-link href)
  `(a (@ (title "回到首页") (href ,href))
      (span (@ (class "home-icon") (aria-hidden "true")) "«")
      "Flora"))

(define (render-flora forest)
  (render-html forest
    #:routes html-routes
    #:style flora-style
    #:title-decoration
    (lambda (_ page)
      (let ((taxon (page-taxon page)))
        (if taxon (taxon-entry-sxml taxon) '())))
      #:article? #t
      #:backmatter-details? #t
      ;; 边注在渲染期抬入页面级 lane:锚点留编号上标,注释按文档序
      ;; 收进 .margin-lane,各带回链——不再依赖 theme.js 搬运 DOM。
      #:side-lane '(flora-sidenote)
      #:backmatter-labels '((context . "语境")
                            (references . "参考文献")
                            (backlinks . "反向链接")
                            (related . "相关"))
      #:html-attributes '((lang . "zh-CN"))
      #:head flora-head
      #:home-link flora-home-link
      #:site-nav (list theme-controls-sxml)))

(define (analyze-flora site)
  ((module-ref (resolve-interface '(flora queries)) 'analyze-flora) (lp-enrich-site site)))

(define flora-project
  (make-site-project
    #:tree-template
    (lambda (id date)
      (string-append
        "@use-modules[(flora commands) (language scribble commands)]\n\n"
        "@title{}\n"
        "@published{" date "}\n"))
    #:title "Flora"
    #:description "A garden of connected notes."
    #:source-directory plant-directory
    #:extra-sources (append (list stylesheet-path feed-stylesheet-path
                                  theme-script-path)
                            font-sources
                            (map (lambda (rel)
                                   (string-append asset-directory "/" rel))
                                 (asset-files asset-directory)))
    #:prepare prepare-flora
    #:read-page
    (make-page-reader read-flora-page-document)
    #:analyze analyze-flora
    #:renderers (list render-flora lp-artifacts flora-sitemap flora-rss
                      (make-cjk-font-renderer
                        (project-directory% "/fonts-src") output-directory
                        #:extra-text interface-text))
    #:output-directory output-directory))

flora-project
