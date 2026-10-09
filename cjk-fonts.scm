;;; CJK webfont subsetting for Flora.

(define-module (cjk-fonts)
  #:use-module (gcrypt hash)
  #:use-module (ice-9 binary-ports)
  #:use-module (ice-9 match)
  #:use-module (rnrs bytevectors)
  #:use-module (forester site)
  #:use-module (grove output)
  #:use-module (grove private cache-dir)
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

(define (hex-digest digest)
  (let ((digits "0123456789abcdef"))
    (list->string
     (append-map
      (lambda (byte)
        (list (string-ref digits (quotient byte 16))
              (string-ref digits (modulo byte 16))))
      (bytevector->u8-list digest)))))

(define (pyftsubset-available?)
  (let ((path (getenv "PATH")))
    (and path (search-path (parse-path path) "pyftsubset") #t)))

(define (subset-fingerprint source-path text)
  ;; Source identity plus codepoint-set identity: a rebuilt font or a
  ;; growing site changes one of them and the cache misses once.
  (let ((attributes (stat source-path)))
    (hex-digest
     (sha256
      (string->utf8
       (string-append (basename source-path)
                      ":" (number->string (stat:size attributes))
                      ":" (number->string (stat:mtime attributes))
                      ":" (hex-digest (sha256 (string->utf8 text)))))))))

(define (subset-font cache-root text-path text source-path)
  ;; Path to a cached woff2 for SOURCE-PATH covering TEXT, subsetting on
  ;; a cache miss. The .partial output keeps a failed run from leaving a
  ;; broken font where the next build would pick it up.
  (let* ((cached (string-append cache-root "/"
                                (basename source-path ".otf") "-"
                                (subset-fingerprint source-path text)
                                ".woff2"))
         (partial (string-append cached ".partial")))
    (unless (file-exists? cached)
      (let ((status (system* "pyftsubset" source-path
                             (string-append "--text-file=" text-path)
                             (string-append "--output-file=" partial)
                             "--flavor=woff2"
                             "--layout-features=*"
                             "--no-hinting"
                             "--desubroutinize")))
        (if (and (number? status) (zero? status))
            (rename-file partial cached)
            (begin
              (when (file-exists? partial) (delete-file partial))
              (error "pyftsubset failed" source-path status)))))
    cached))

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
                                                source-path)
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
