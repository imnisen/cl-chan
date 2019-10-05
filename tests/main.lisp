(defpackage cl-chan/tests/main
  (:use :cl
        :cl-chan
        :rove))
(in-package :cl-chan/tests/main)

;; NOTE: To run this test file, execute `(asdf:test-system :cl-chan)' in your Lisp.

(deftest test-target-1
  (testing "should (= 1 1) to be true"
    (ok (= 1 1))))
