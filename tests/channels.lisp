;;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Base: 10; indent-tabs-mode: nil -*-
;;;;
;;;; This Test is copy and edit from  https://github.com/zkat/chanl/
;;;;
;;;; Copyright © 2009 Kat Marchan, Adlai Chandrasekhar
;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(in-package :cl-chan)

(def-suite channels :in cl-chan)
(def-suite construction :in channels)
(in-suite construction)

(test make-unbuffered
  (let ((chan (make-instance 'unbuffered-channel)))
    (is (channelp chan))
    (is (not (channel-buffered-p chan)))
    (is (= 0 (channel-readers-waiting chan)))
    (is (= 0 (channel-writers-waiting chan)))
    (is (eq *secret-unbound-value* (channel-value chan)))
    ;; (is (send-blocks-p chan))
    ;; (is (recv-blocks-p chan))

    ;; We don't really have predicates for these, but if they exist, we assume
    ;; they're what they're suposed to be.
    (is (channel-lock chan))
    (is (channel-send-ok chan))
    (is (channel-recv-ok chan))))

(test make-buffered
  (let ((chan (make-instance 'buffered-channel :size 10)))
    (is (channelp chan))
    (is (channel-buffered-p chan))
    (is (queuep (channel-queue chan)))
    (is (= 10 (queue-length (channel-queue chan))))
    (is (= 0 (channel-readers-waiting chan)))
    (is (= 0 (channel-writers-waiting chan)))
    ;; (is (not (send-blocks-p chan)))
    ;; (is (recv-blocks-p chan))

    ;; We don't really have predicates for these, but if they exist, we assume
    ;; they're what they're suposed to be.
    (is (channel-lock chan))
    (is (channel-send-ok chan))
    (is (channel-recv-ok chan))))


(test make-invalid
      (signals error (make-instance 'buffered-channel :size nil))
      (signals error (make-instance 'buffered-channel :size -1)))

(def-suite messaging :in channels)
(def-suite sending :in messaging)
(in-suite sending)

(test send-unbuffered
  (let ((channel (make-instance 'unbuffered-channel)))
    (is (null (send channel 'test :blockp nil)))
    (pexec () (recv channel))
    (is (eq channel (send channel 'test)))

    (pexec () (recv channel))
    (is (eq channel (send channel 'test)))

    (pexec () (recv channel))
    (sleep 0.5) ;hax to let the thread start working
    (is (eq channel (send channel 'test :blockp nil)))
    ))

(test send-buffered
      (let ((channel (make-instance 'buffered-channel :size 1)))
        ;; (is (eq channel (send channel 'test :blockp nil)))
        ;; (recv channel)
        (is (eq channel (send channel 'test)))
        ;; (is (null (send channel 'test :blockp nil)))
        (pexec () (recv channel))
        (is (eq channel (send channel 'test)))
        (pexec () (recv channel))))


(def-suite receiving :in messaging)
(in-suite receiving)

(test recv-unbuffered
  (let ((channel (make-instance 'unbuffered-channel)))
    (is (null (nth-value 1 (recv channel :blockp nil))))
    (is (null (values (recv channel :blockp nil))))
    (pexec () (send channel 'test))
    (multiple-value-bind (value rec-chan)
        (recv channel)
      (is (eq channel rec-chan))
      (is (eq 'test value)))
    ;; repeat it just to make sure it doesn't fuck up the second time around
    (pexec () (send channel 'test))
    (multiple-value-bind (value rec-chan)
        (recv channel)
      (is (eq channel rec-chan))
      (is (eq 'test value)))
    (pexec () (send channel 'test))
    (sleep 0.5)
    (is (eq 'test (recv channel :blockp nil)))
    ))

(test recv-buffered
  (let ((channel (make-instance 'buffered-channel :size 1)))
    ;; (is (null (recv channel :blockp nil)))
    ;; (is (null (nth-value 1 (recv channel :blockp nil))))
    (send channel 'test)
    (multiple-value-bind (value rec-chan)
        (recv channel)
      (is (eq channel rec-chan))
      (is (eq 'test value)))
    ;; (is (null (recv channel :blockp nil)))
    ;; (is (null (nth-value 1 (recv channel :blockp nil))))
    (pexec () (send channel 'test))
    (is (eq 'test (recv channel)))))


(def-suite racing :in channels)
(in-suite racing)

(defun setup-race (thread-count class &rest channel-args)
  (let ((lock (bt:make-lock "bt:semaphore")) (nrx 0) (ntx 0) start
        (channel (apply #'make-instance class channel-args)))
    (macrolet ((with-counter ((place) &body body)
                 `(unwind-protect
                       (progn (bt:with-lock-held (lock) (incf ,place)) ,@body)
                    (bt:with-lock-held (lock) (decf ,place))))
               (await (place) `(loop :until (= ,place thread-count))))
      (flet ((recver () (with-counter (nrx) (recv channel)))
             (sender (x)
               (lambda ()
                 (with-counter (ntx)
                   (loop :until start :do (bt:thread-yield))
                   (send channel x))))
             (strcat (&rest things) (format () "~{~A~}" things)))
        (let ((threads (loop :for n :below thread-count
                             :collect (bt:make-thread #'recver :name (strcat "r" n))
                             :collect (bt:make-thread (sender n) :name (strcat "s" n)))))
          (await nrx) (await ntx) (setf start t)
          (values threads channel))))))

(test racing
  (macrolet ((test-case (class count kind)
               `(multiple-value-bind (threads channel) (setup-race ,count ',class)
                  (let* ((pass nil)
                         (verifier (pexec ()
                                     (mapc #'bt:join-thread threads)
                                     (setf pass t))))
                    (sleep 5) ;; 5s maybe enough for max 15 threads to finish. you can set this by your wish.
                    (is (eq pass t)
                        (concatenate
                         'string ,(format () "count=~D, ~A" count kind)
                         (with-output-to-string (*standard-output*)
                           (format t "~%~%Contested Channel:~%")
                           (describe channel)
                           (format t "~%~%Competing Threads:~%")
                           (mapc 'describe
                                 (remove () threads
                                         :key #'bt:thread-alive-p)))))
                    (unless pass
                      (mapc #'bt:destroy-thread
                            (remove () threads
                                    :key #'bt:thread-alive-p))
                      (kill (task-thread verifier)))))))
    (test-case unbuffered-channel 3 "unbuffered")
    (test-case unbuffered-channel 6 "unbuffered")
    (test-case unbuffered-channel 15 "unbuffered")
    ))
