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
             (forester render site)
             (forester render sitemap)
             (forester style i18n)
             (grove input scribble)
             (grove pipeline)
             (grove project)
             (grove project site)
             (grove render html routes)
             (forester site)
             (grove site)
             (grove ir)
             (lp forester)
             (grove render html)
             (grove render html image)
             (grove render html rules)
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

;; 图片资产:blazek2005 的插图由管线从扫描版 PDF 按裁剪清单再生,
;; 不入库;@image 引用的 URL 与旧的目录布局一致(/blazek2005/fig-*.png)。
;; 身份覆盖 project.scm 与两份输入——改裁剪框或换 PDF 版本即失效再生。
(define blazek2005-pdf
  (project-directory%
   "/materials/books/Computational Fluid Dynamics Principles and Appl.pdf"))
(define blazek2005-manifest
  (project-directory% "/docs/blazek2005-figures.tsv"))
(define figure-page-cache
  (string-append (or (getenv "TMPDIR") "/tmp") "/flora-figure-pages"))

(define image-tool
  ;;     ImageMagick 7 命令名为 magick,Guix 仍是 IM6 的 convert。
  (if (zero? (system "magick -version >/dev/null 2>&1")) "magick" "convert"))

(define (figure-manifest path)
  ;; name page x y w h(200 dpi 渲染;PDF 页 = 印刷页 + 21)
  (filter-map
   (lambda (line)
     (and (not (string-null? line))
          (not (string-prefix? "#" line))
          (let ((fields (string-split line #\tab)))
            (cons (car fields)
                  (map string->number (cdr fields))))))
   (string-split (call-with-input-file path get-string-all) #\newline)))

(define (render-page pdf page)
  ;; pdftoppm 的输出名带零填充页号;每页只光栅化一次。
  (let* ((padded (format #f "~3,'0d" page))
         (cached (string-append figure-page-cache "/p" padded ".png"))
         (prefix (string-append figure-page-cache "/tmp" padded)))
    (unless (file-exists? cached)
      (unless (file-exists? figure-page-cache)
        (mkdir figure-page-cache))
      (unless (zero? (system* "pdftoppm" "-png" "-r" "200"
                              "-f" (number->string page)
                              "-l" (number->string page)
                              pdf prefix))
        (error "pdftoppm failed" page))
      (rename-file (string-append prefix "-" padded ".png") cached))
    cached))


(define (encode-variant command args output)
  (let ((temporary (string-append figure-page-cache "/" (basename output))))
    (unless (zero? (apply system* command (append args (list temporary))))
      (error "image encode failed" command output))
    (let ((bytes (call-with-input-file temporary get-bytevector-all #:binary #t)))
      (delete-file temporary)
      bytes)))
(define blazek2005-figures
  (make-asset-pipeline
   #:name "blazek2005-figures"
   #:inputs (list blazek2005-pdf blazek2005-manifest)
   #:procedure
   (lambda (in emit)
     (let ((pdf (in blazek2005-pdf)))
       (for-each
        (lambda (figure)
          (let* ((name (car figure))
                 (box (cdr figure))
                 (page (list-ref box 0))
                 (x (list-ref box 1))
                 (y (list-ref box 2))
                 (w (list-ref box 3))
                 (h (list-ref box 4))
                 (page-png (render-page pdf page))
                 (cropped (string-append figure-page-cache "/crop-" name)))
            (unless (zero? (system* image-tool page-png "-crop"
                                    (format #f "~ax~a+~a+~a" w h x y)
                                    "+repage" cropped))
              (error "figure crop failed" name))
            (let* ((base (string-drop-right name 4))
                   (png (string-append "blazek2005/" name))
                   (avif (string-append "blazek2005/" base ".avif")))
              (emit png
                    (call-with-input-file cropped get-bytevector-all))
              (emit avif
                    (encode-variant
                      "avifenc" (list "-q" "60" "-s" "8" cropped)
                      avif)))))
        (figure-manifest (in blazek2005-manifest)))))))
(define figure-image-sets
  (map (lambda (name)
         (let ((base (string-drop-right name 4)))
           (cons (string-append "blazek2005/" name)
                 (make-image-set
                   (string-append "blazek2005/" name)
                   #:variants
                   (list
                     (make-image-variant
                       "image/avif"
                       (string-append "/blazek2005/" base ".avif")))
                   #:fallback
                   (string-append "/blazek2005/" name)))))
       (map car (figure-manifest blazek2005-manifest))))

(define flora-rules
  (make-html-rules
    (list (cons 'image (image-set-rule figure-image-sets)))))
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
        font-assets))))

(define html-routes (make-html-routes #:home-page "flora"))

(define flora-locale "zh-Hans")
(define flora-settings
  (make-site-settings #:site-url "https://flora.purejs.icu"
                      #:default-locale flora-locale))

;; Interface strings rendered outside the trees: backmatter labels and the
;; theme controls. The font subset must carry their glyphs even though no
;; tree happens to contain them.
(define interface-text
  (string-append "语境参考文献反向链接相关"
                 "回到首页"
                 "站点配色设置跟随系统配色使用日间配色使用夜间配色"
                 "跳到正文站点导航目录将树作为页面打开更新于年月日"))
(define flora-sitemap
  (make-sitemap-renderer
    #:settings flora-settings
    #:routes html-routes))
(define flora-rss
  (make-rss-renderer
    #:settings flora-settings
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
    #:settings flora-settings
    #:locale flora-locale
    #:style flora-style
    #:rules flora-rules
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
        "@use-commands{flora}\n\n"
        "@title{}\n"
        "@published{" date "}\n"))
    #:title "Flora"
    #:locale flora-locale
    #:description "A garden of connected notes."
    #:source-directory plant-directory
    #:extra-sources (append (list stylesheet-path feed-stylesheet-path
                                  theme-script-path)
                            font-sources)
    #:prepare prepare-flora
    #:read-page
    (make-page-reader read-flora-page-document)
    #:analyze analyze-flora
    #:renderers (list render-flora lp-artifacts flora-sitemap flora-rss
                      (make-cjk-font-renderer
                        (project-directory% "/fonts-src") output-directory
                        #:extra-text interface-text))
    #:pipelines (list blazek2005-figures)
    #:output-directory output-directory))

flora-project
