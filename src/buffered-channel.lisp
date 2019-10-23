;;;
;;; Buffered channels (bounded)
;;;

(in-package :cl-chan)

(defclass buffered-channel (abstract-channel)
  ((queue :accessor channel-queue)

   (lock :initform (bt:make-lock) :accessor channel-lock) ;; protect multi senders and recvers
   (send-ok :initform (bt:make-condition-variable) :accessor channel-send-ok)  ;; recver notify sender
   (recv-ok :initform (bt:make-condition-variable) :accessor channel-recv-ok)  ;; sender notify recver
   (recvers-waiting :initform 0 :accessor channel-recvers-waiting) ;; how many recvers waiting for recv
   (senders-waiting :initform 0 :accessor channel-senders-waiting))) ;; how many senders waiting for send


(defconstant +maximum-buffer-size+ (- array-total-size-limit 2)
  "The exclusive upper bound on the size of a channel's buffer.")

(defmethod initialize-instance :after ((channel buffered-channel) &key (size 1))
  (assert (typep size `(integer 1 ,(1- +maximum-buffer-size+))) (size)
          "Buffer size must be a non-negative fixnum..")
  (setf (channel-queue channel) (make-queue size)))

;;; Check if it is buffered channel
(defgeneric channel-bufferedp (channel)
  (:method ((anything-else t)) nil)
  (:method ((channel buffered-channel)) t))

(defmethod send ((channel buffered-channel) value &key (blockp t))
  (with-accessors ((lock channel-lock)
                   (queue channel-queue)
                   (senders-waiting channel-senders-waiting)
                   (recvers-waiting channel-recvers-waiting)
                   (recv-ok channel-recv-ok)
                   (send-ok channel-send-ok))
      channel
    (bt:with-lock-held (lock)
      (loop :while (queue-full-p queue)
            :if blockp :do (progn
                             (incf senders-waiting)
                             (bt:condition-wait send-ok lock)
                             (decf senders-waiting))
            :else :do (return-from send nil))
      (enqueue value queue)
      (when (> recvers-waiting 0)
        (bt:condition-notify recv-ok))
      channel)))

;;; Receive value from buffered channel
(defmethod recv ((channel buffered-channel) &key (blockp t))
  (with-accessors ((lock channel-lock)
                   (queue channel-queue)
                   (senders-waiting channel-senders-waiting)
                   (recvers-waiting channel-recvers-waiting)
                   (recv-ok channel-recv-ok)
                   (send-ok channel-send-ok))
      channel
    (bt:with-lock-held (lock)
      (loop :while (queue-empty-p queue)
            :if blockp :do (progn
                             (incf recvers-waiting)
                             (bt:condition-wait recv-ok lock)
                             (decf recvers-waiting))
            :else :do (return-from recv (values nil nil)))

      (multiple-value-prog1
          (values (dequeue queue) channel)
        (when (> senders-waiting 0)
          (bt:condition-notify send-ok))
        ))))
