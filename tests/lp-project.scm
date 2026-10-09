;;; Run: guile --no-auto-compile -L . tests/lp-project.scm
;;; No Grove imports: test actual module boundaries and independent output.
(use-modules (lp core) (lp project) (srfi srfi-64) (srfi srfi-13) (srfi srfi-1) (ice-9 ftw))
(test-begin "lp-project")
(define origin '((file . "sample.plant") (line . 7) (column . 3)))
(define seed (make-fragment "seed" "Seed" '((define seed 3)) #:origins (list origin)))
(define answer (make-fragment "answer" "Answer" '((define answer (+ seed 1)))
                #:initial-requires '(seed) #:origins (list origin)))
(define (message thunk)
  (catch #t (lambda () (thunk) #f)
    (lambda (key . args) (format #f "~s ~s" key args))))
(test-equal "declared initialization succeeds" 4
  (instance-binding (instantiate-program (make-program "ordered" "Ordered" (list seed answer) '(answer))) 'answer))
(define order-error (message (lambda () (make-program "reversed" "Reversed" (list answer seed) '(answer)))))
(test-assert "initialization error names plan, fragment, binding and source"
  (and (string-contains order-error "reversed") (string-contains order-error "answer")
       (string-contains order-error "seed") (string-contains order-error "sample.plant")))
(define duplicate-error
  (message (lambda () (make-program "duplicate" "Duplicate"
                        (list seed (make-fragment "second" "Second" '((define seed 9))
                                     #:origins (list origin))) '(seed)))))
(test-assert "duplicate definition names both fragment providers"
  (and (string-contains duplicate-error "seed") (string-contains duplicate-error "second")
       (string-contains duplicate-error "sample.plant")))
(define runtime-error
  (message (lambda ()
             (instantiate-program
               (make-program "runtime-order" "Runtime order"
                 (list (make-fragment "eager" "Eager" '((define answer seed))
                         #:requires '(seed) #:origins (list origin)) seed) '(answer))))))
(test-assert "undeclared initializer order reports plan, fragment, source and cause"
  (and (string-contains runtime-error "runtime-order") (string-contains runtime-error "eager")
       (string-contains runtime-error "sample.plant") (string-contains runtime-error "unbound-variable")))
(define provider
  (make-program "provider" "Provider"
    (list (make-fragment "counter-module" "Counter"
            '((define value 0) (define (next) (set! value (+ value 1)) value)))) '(next)))
(define consumer
  (make-program "consumer" "Consumer"
    (list (make-fragment "consumer-body" "Consumer" '((define (run) (next))) #:requires '(next))) '(run)
    #:imports (list (make-import '(lp-test provider) '(next)))))
(define provider-output (make-module-output '(lp-test provider) provider))
(define consumer-output (make-module-output '(lp-test consumer) consumer))
(define project (make-project "example" "Example" (list provider-output consumer-output)))
(define one (instantiate-project project))
(define two (instantiate-project project))
(test-equal "selected project import executes" 1 ((project-binding one '(lp-test consumer) 'run)))
(test-equal "import aliases retain provider state" 2 ((project-binding one '(lp-test consumer) 'run)))
(test-equal "independent projects isolate provider state" 1 ((project-binding two '(lp-test consumer) 'run)))
(test-error "private project binding rejected" #t (project-binding one '(lp-test provider) 'value))
(test-error "consumer cannot export imported binding" #t
  (make-program "bad-export" "Bad export" (program-fragments consumer) '(next)
    #:imports (program-imports consumer)))
(test-error "unknown project module rejected" #t (project-binding one '(lp-test absent) 'run))
(test-error "project order is explicit" #t
  (make-project "order" "Order" (list consumer-output provider-output)))
(test-error "circular module imports rejected" #t
  (make-project "cycle" "Cycle"
    (list
      (make-module-output '(lp-test a)
        (make-program "cycle-a" "Cycle A"
          (list (make-fragment "a" "A" '((define (a) (b))) #:requires '(b))) '(a)
          #:imports (list (make-import '(lp-test b) '(b)))))
      (make-module-output '(lp-test b)
        (make-program "cycle-b" "Cycle B"
          (list (make-fragment "b" "B" '((define (b) (a))) #:requires '(a))) '(b)
          #:imports (list (make-import '(lp-test a) '(a))))))))
(test-error "unexported project import rejected" #t
  (make-project "hidden" "Hidden"
    (list provider-output
          (make-module-output '(lp-test hidden)
            (make-program "hidden-consumer" "Hidden consumer"
              (list (make-fragment "read-hidden" "Hidden" '((define (run) value)) #:requires '(value))) '(run)
              #:imports (list (make-import '(lp-test provider) '(value))))))))
(test-error "duplicate outputs rejected" #t
  (make-project "duplicates" "Duplicates" (list provider-output provider-output)))
(test-error "import conflicts with local binding" #t
  (make-program "conflict" "Conflict" (program-fragments provider) '(next)
    #:imports (list (make-import '(lp-test external) '(next)))))
(test-equal "explicit external import executes" 25
  ((instance-binding
     (instantiate-program
       (make-program "external" "External"
         (list (make-fragment "square" "Square" '((define (square x) (expt x 2))) #:requires '(expt))) '(square)
         #:imports (list (make-import '(guile) '(expt))))) 'square) 5))
(test-assert "nested module output path" (valid-output-path? (module-output-path consumer-output)))
(test-assert "path traversal, absolute paths and empty components rejected"
  (not (any valid-output-path? '("../x.scm" "/x.scm" "x//y.scm" "x/../y.scm" "x\\y.scm" ".scm"))))
(test-assert "module export does not execute initializer"
  (string-contains
    (module-output-source
      (make-module-output '(lp-test dormant)
        (make-program "dormant" "Dormant"
          (list (make-fragment "dormant-body" "Dormant" '((define value (throw 'executed))))) '(value)))) "executed"))
;; Export into a temporary directory, then load the result in a separate Guile
;; process. This catches differences between in-memory assembly and Guile files.
(define temp (mkdtemp "/tmp/flora-lp-project-XXXXXX"))
(mkdir (string-append temp "/lp-test"))
(for-each
  (lambda (output)
    (call-with-output-file (string-append temp "/" (module-output-path output))
      (lambda (port) (display (module-output-source output) port)))) (project-outputs project))
(test-equal "exported modules run without Grove or LP library" 0
  (status:exit-val
    (system* (readlink "/proc/self/exe")
             "--no-auto-compile" "-L" temp "-c"
             "(use-modules (lp-test consumer)) (unless (equal? (list (run) (run)) '(1 2)) (exit 1))")))
(for-each (lambda (output) (delete-file (string-append temp "/" (module-output-path output)))) (project-outputs project))
(rmdir (string-append temp "/lp-test")) (rmdir temp)
(define failures (+ (test-runner-fail-count (test-runner-current)) (test-runner-xpass-count (test-runner-current))))
(test-end "lp-project")
(exit (if (zero? failures) 0 1))
