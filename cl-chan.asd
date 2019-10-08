(defsystem "cl-chan"
  :version "0.1.0"
  :author "Nisen"
  :license "BSD"
  :depends-on ("bordeaux-threads")
  :components ((:module "src"
                :components
                ((:file "packages")
                 (:file "utils")
                 (:file "threads")
                 (:file "queues")
                 (:file "main"))))
  :description ""
  :in-order-to ((test-op (test-op "cl-chan/tests"))))

(defsystem "cl-chan/tests"
  :author "Nisen"
  :license "BSD"
  :depends-on ("cl-chan"
               "fiveam")
  :serial t
  :components ((:module "tests"
                :serial t
                :components
                ((:file "setup-tests")
                 (:file "channels"))))
  :description "Test system for cl-chan"
  :perform
  (test-op (o c)
           (format t "~2&*******************~@
                  ** Starting test **~@
                  *******************~%")
           (handler-bind ((style-warning #'muffle-warning))
             (symbol-call :cl-chan :run-all-tests))
           (format t "~2&*****************************************~@
                  **            Tests finished           **~@
                  *****************************************~@
                  ** If there were any failures, please  **~@
                  **      file a bugreport on github:    **~@
                  **     github.com/imnisen/cl-chan/issues    **~@
                  *****************************************~%"))
  ;; (test-op (op c) (symbol-call :rove :run c))
  )
