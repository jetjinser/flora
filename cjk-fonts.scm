;;; CJK webfont subsetting for Flora.

(define-module (cjk-fonts)
  #:use-module (ice-9 binary-ports)
  #:use-module (ice-9 match)
  #:use-module (forester site)
  #:use-module (grove output)
  #:use-module (grove private cache-dir)
  #:use-module (grove private fingerprint)
  #:use-module (grove private pipeline)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:export (make-cjk-font-renderer))

;; ASCII plus the punctuation chrome strings and future notes plausibly
;; need; used-codepoints covers what the trees actually say today.
(define %ascii
  (list->string (map integer->char (iota 95 32))))

(define %punctuation-buffer
  (list->string
   (map integer->char
        (list #x00A0                    ; no-break space
              #x00AD                    ; soft hyphen
              #x00B7                    ; middle dot
              #x2013 #x2014             ; en and em dash
              #x2018 #x2019 #x201C #x201D
              #x2026                    ; ellipsis
              #x3001 #x3002             ; ideographic comma and full stop
              #x3008 #x3009 #x300A #x300B
              #x300C #x300D #x300E #x300F
              #x3010 #x3011 #x3014 #x3015
              #xFF01 #xFF08 #xFF09 #xFF0C
              #xFF1A #xFF1B #xFF1F))))

;; family, weight, source file in fonts-src/, artifact name under fonts/.
;; Serif Light backs the 300-weight metadata line, Regular the body,
;; Bold the headings; Sans 400 covers the navigation and contents. The
;; family names are the ones style.css already lists, so the stacks need
;; no edits when the webfonts appear.
(define %cjk-fonts
  '(("Noto Serif CJK SC" 300 "NotoSerifCJKsc-Light.otf"   "noto-serif-sc-300.woff2")
    ("Noto Serif CJK SC" 400 "NotoSerifCJKsc-Regular.otf" "noto-serif-sc-400.woff2")
    ("Noto Serif CJK SC" 700 "NotoSerifCJKsc-Bold.otf"    "noto-serif-sc-700.woff2")
    ("Noto Sans CJK SC"  400 "NotoSansCJKsc-Regular.otf"  "noto-sans-sc-400.woff2")))

(define (pyftsubset-available?)
  (let ((path (getenv "PATH")))
    (and path (search-path (parse-path path) "pyftsubset") #t)))

(define (subset-identity source-path text)
  ;; Content identity: source font bytes plus the codepoint set. No
  ;; stat, no mtime - the same inputs hit the same store blobs from
  ;; any checkout.
  (content-fingerprint
   (string-append "flora-cjk-subset:" (basename source-path)
                  ":" (file-fingerprint source-path)
                  ":" (content-fingerprint text))))

(define (subset-font cache-root text-path text source-path output)
  ;; A woff2 for SOURCE-PATH covering TEXT, staged through the shared
  ;; store: a hit restores without running pyftsubset at all, a miss
  ;; runs it and publishes the blob for every other checkout. The
  ;; .partial output keeps a failed run from leaving a broken font
  ;; where the next build would pick it up.
  (let* ((identity (subset-identity source-path text))
         (cached (string-append cache-root "/"
                                (basename source-path ".otf") "-"
                                identity
                                ".woff2"))
         (partial (string-append cached ".partial")))
    (or (let ((bytes (restore-boundary-bytes identity)))
          (and bytes
               (ensure-directory cache-root)
               (call-with-output-file cached
                 (lambda (port) (put-bytevector port bytes))
                 #:binary #t)
               cached)))
        (begin
          (ensure-directory cache-root)
          (let ((status (system* "pyftsubset" source-path
                                 (string-append "--text-file=" text-path)
                                 (string-append "--output-file=" partial)
                                 "--flavor=woff2"
                                 "--layout-features=*"
                                 "--no-hinting"
                                 "--desubroutinize")))
            (unless (and (number? status) (zero? status))
              (when (file-exists? partial) (delete-file partial))
              (error "pyftsubset failed" source-path status)))
          (let ((bytes (call-with-input-file partial get-bytevector-all
                         #:binary #t)))
            (when (file-exists? partial) (delete-file partial))
            (write-boundary-index identity
                                  (list (cons output (publish-boundary-bytes bytes))))
            (call-with-output-file cached
              (lambda (port) (put-bytevector port bytes))
              #:binary #t)
            cached))))

(define (font-face-sxml family weight output)
  (format #f "@font-face {
  font-family: '~a';
  font-style: normal;
  font-weight: ~d;
  font-display: swap;
  src: url(/fonts/~a) format('woff2');
}
" family weight output))

(define* (make-cjk-font-renderer source-directory output-directory
                                 #:key (extra-text ""))
  (lambda (forest)
    (let* ((text (string-append %ascii %punctuation-buffer extra-text
                                (list->string (used-codepoints forest))))
           (cache-root (string-append
                        (grove-cache-directory output-directory)
                        "/cjk-fonts"))
           (text-path (string-append cache-root "/codepoints.txt"))
           (available? (pyftsubset-available?)))
      (ensure-directory cache-root)
      (unless available?
        (format (current-error-port)
                "grove: pyftsubset not on PATH; CJK text falls back to system fonts~%"))
      (call-with-output-file text-path (lambda (port) (display text port)))
      (let ((faces
             (append-map
              (lambda (spec)
                (match spec
                  ((family weight source output)
                   (let ((source-path (string-append source-directory "/" source)))
                     (cond
                      ((not available?)
                       '())
                      ((not (file-exists? source-path))
                       (format (current-error-port)
                               "grove: missing CJK source font ~a; run fetch-fonts.sh~%"
                               source-path)
                       '())
                      (else
                       (list
                        (cons spec
                              (make-byte-artifact
                               (string-append "fonts/" output)
                               (call-with-input-file
                                   (subset-font cache-root text-path text
                                                source-path output)
                                 get-bytevector-all
                                 #:binary #t)
                               (list source-path text-path))))))))))
              %cjk-fonts)))
        (cons (make-artifact "fonts/cjk.css"
                (if (null? faces)
                    "/* CJK webfonts unavailable; the system-font stacks in style.css apply. */\n"
                    (string-join
                     (map (match-lambda
                            ((family weight _ output)
                             (font-face-sxml family weight output)))
                          (map car faces))
                     ""))
                (list (current-filename)))
              (map cdr faces)))))) 
