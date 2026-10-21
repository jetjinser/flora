;;; SPDX-FileCopyrightText: 2026 Jinser Kafka <aimer@purejs.icu>
;;;
;;; SPDX-License-Identifier: GPL-3.0-or-later

;;; The command set pages import with @use-commands{flora}.  Keeping the
;;; manifest outside plants/ avoids turning it into a page.

(define-module (flora)
  #:export (command-modules))

(define-public command-modules
  '((forester commands) (flora commands)))
