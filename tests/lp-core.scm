;;; Run: guile --no-auto-compile -L . tests/lp-core.scm
;;; The core suite deliberately imports no Grove or Flora modules.
(use-modules (lp core) (lp check) (srfi srfi-64) (srfi srfi-13))
(test-begin "lp-core")
(define counter-fragment
  (make-fragment "counter" "Counter"
    '((define count 0)
      (define (increment) (set! count (+ count 1)) count))))
(define counter-program (make-program "counter-program" "Counter program"
                         (list counter-fragment) '(increment)))
(define first-instance (instantiate-program counter-program))
(define second-instance (instantiate-program counter-program))
(test-equal "first instance starts at one" 1 ((instance-binding first-instance 'increment)))
(test-equal "same instance retains state" 2 ((instance-binding first-instance 'increment)))
(test-equal "another instance has independent state" 1 ((instance-binding second-instance 'increment)))
(test-error "private binding unavailable" #t (instance-binding first-instance 'count))

(define dormant (make-fragment "dormant" "Dormant"
                  '((define bad (throw 'initializer-executed)))))
(define dormant-program (make-program "dormant-program" "Dormant program" (list dormant) '(bad)))
(test-assert "source output doesn't run initializer"
  (string-contains (program-source dormant-program) "initializer-executed"))
(test-error "explicit instantiation runs initializer" #t (instantiate-program dormant-program))
(test-error "duplicate fragment rejected" #t
  (make-program "duplicate" "Duplicate" (list counter-fragment counter-fragment) '(increment)))
(test-error "duplicate definition rejected" #t
  (make-program "duplicate-def" "Duplicate definition"
    (list counter-fragment (make-fragment "other" "Other" '((define count 10)))) '(increment)))
(test-error "unknown export rejected" #t
  (make-program "exports" "Exports" (list counter-fragment) '(missing)))
(test-error "missing dependency rejected" #t
  (make-program "missing" "Missing"
    (list (make-fragment "consumer" "Consumer" '((define (f) (missing)))
            #:requires '(missing))) '(f)))

(define quoted-fragment
  (make-fragment "quoted" "Quoted" '((define env '((x . 3))))
    #:texts '("(define env '((x . 3))) ; retained comment")))
(define quoted-program (make-program "quoted-program" "Quoted program" (list quoted-fragment) '(env)))
(test-assert "original comment retained" (string-contains (program-source quoted-program) "retained comment"))
(test-equal "source and executable datums agree" (program-datums quoted-program)
  (call-with-input-string (program-source quoted-program)
    (lambda (port)
      (let loop ((forms '()))
        (let ((form (read port)))
          (if (eof-object? form) (reverse forms) (loop (cons form forms))))))))
(test-equal "dotted quoted data executes" '((x . 3))
  (instance-binding (instantiate-program quoted-program) 'env))
(test-equal "plain result check" 4 (check-equal "example" 4 4))
(test-error "result mismatch fails" #t (check-equal "example" 4 5))
(test-equal "finite check returns count" 3 (check-samples "property" '(1 2 3) positive?))
(test-error "counterexample fails" #t (check-samples "property" '(1 -1) positive?))
(test-equal "expected exception" 'sample (check-error "error" (lambda () (throw 'sample)) 'sample))
(test-error "missing exception fails" #t (check-error "error" (lambda () 1) 'sample))
(test-error "unexpected exception propagates" #t (check-error "error" (lambda () (throw 'different)) 'sample))
(define failures (+ (test-runner-fail-count (test-runner-current))
                    (test-runner-xpass-count (test-runner-current))))
(test-end "lp-core")
(exit (if (= failures 0) 0 1))
