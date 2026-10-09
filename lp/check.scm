;;; SPDX-License-Identifier: CC0-1.0
(define-module (lp check)
  #:export (check-equal check-samples check-error))

;; Checks return data; they do not construct document nodes.
(define* (check-equal id actual expected #:key origin)
  (unless (equal? actual expected)
    (error "LP result mismatch" id origin actual expected))
  actual)

(define* (check-samples id samples predicate #:key origin)
  (let loop ((remaining samples) (count 0))
    (if (null? remaining) count
        (if (predicate (car remaining))
            (loop (cdr remaining) (+ count 1))
            (error "LP property counterexample" id origin (car remaining))))))

(define* (check-error id thunk expected-key #:key origin)
  (let ((outcome (catch #t
                   (lambda () (list 'returned (thunk)))
                   (lambda (key . arguments)
                     (if (eq? key expected-key) (list 'expected key)
                         (apply throw key arguments))))))
    (unless (eq? (car outcome) 'expected)
      (error "LP expected an exception" id origin expected-key outcome))
    expected-key))
