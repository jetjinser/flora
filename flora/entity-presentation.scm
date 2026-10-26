;;; SPDX-FileCopyrightText: 2026 Jinser Kafka <aimer@purejs.icu>
;;; SPDX-License-Identifier: GPL-3.0-or-later

(define-module (flora entity-presentation)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:export (entity-metadata-item))

(define (citation-item metadata)
  (let* ((authors (assq-ref metadata 'authors))
         (details
          (filter string?
                  (list (and (pair? authors) (string-join authors ", "))
                        (assq-ref metadata 'year)
                        (assq-ref metadata 'container-title))))
         (title (assq-ref metadata 'title)))
    `(li (@ (class "meta-item external-metadata"))
         "外部文献：" (cite ,title)
         ,@(if (pair? details)
               (list " — " (string-join details " · "))
               '()))))

(define (dataset-item metadata)
  (let ((name (assq-ref metadata 'name))
        (landing-page (assq-ref metadata 'landing-page))
        (creators (assq-ref metadata 'creators))
        (description (assq-ref metadata 'description))
        (license (assq-ref metadata 'license)))
    `(li (@ (class "meta-item external-metadata dataset"))
         "外部数据集："
         ,(if (and (string? landing-page) (string? name))
              `(a (@ (href ,landing-page)) ,name)
              (or name landing-page "（未命名）"))
         ,@(if (and (list? creators) (pair? creators))
               (list " — " (string-join creators ", "))
               '())
         ,@(if (string? description) (list " — " description) '())
         ,@(if (string? license) (list " · 许可：" license) '()))))

(define (entity-metadata-item metadata)
  (case (assq-ref metadata 'type)
    ((citation) (citation-item metadata))
    ((dataset) (dataset-item metadata))
    (else #f)))
