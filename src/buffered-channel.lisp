;;;
;;; Buffered channels (bounded)
;;;

(in-package :cl-chan)

(defclass buffered-channel (abstract-channel)
  ((queue :accessor channel-queue)

   (lock :initform (bt:make-recursive-lock) :accessor channel-lock)

   (send-ok :initform (bt:make-condition-variable) :accessor channel-send-ok)
   (recv-ok :initform (bt:make-condition-variable) :accessor channel-recv-ok)

   (readers-waiting :initform 0 :accessor channel-readers-waiting)
   (writers-waiting :initform 0 :accessor channel-writers-waiting)))


(defconstant +maximum-buffer-size+ (- array-total-size-limit 2)
  "The exclusive upper bound on the size of a channel's buffer.")

(defmethod initialize-instance :after ((channel buffered-channel) &key (size 1))
  (assert (typep size `(integer 1 ,(1- +maximum-buffer-size+))) (size)
          "Buffer size must be a non-negative fixnum..")
  (setf (channel-queue channel) (make-queue size)))

;;; Check if it is buffered channel
(defgeneric channel-buffered-p (channel)
  (:method ((anything-else t)) nil)
  (:method ((channel buffered-channel)) t))

(defmethod send ((channel buffered-channel) value &key (blockp t))
  (with-accessors ((lock channel-lock)
                   (queue channel-queue)
                   (writers-waiting channel-writers-waiting)
                   (readers-waiting channel-readers-waiting)
                   (recv-ok channel-recv-ok)
                   (send-ok channel-send-ok))
      channel
    (bt:with-lock-held (lock)
      (loop :while (queue-full-p queue)
            :if blockp :do (progn
                             (incf writers-waiting)
                             (bt:condition-wait send-ok lock)
                             (decf writers-waiting))
            :else :do (return-from send nil))
      (enqueue value queue)
      (when (> readers-waiting 0)
        (bt:condition-notify recv-ok))
      channel)))

;;; Receive value from buffered channel
(defmethod recv ((channel buffered-channel) &key (blockp t))
  (with-accessors ((lock channel-lock)
                   (queue channel-queue)
                   (writers-waiting channel-writers-waiting)
                   (readers-waiting channel-readers-waiting)
                   (recv-ok channel-recv-ok)
                   (send-ok channel-send-ok))
      channel
    (bt:with-lock-held (lock)
      (loop :while (queue-empty-p queue)
            :if blockp :do (progn
                             (incf readers-waiting)
                             (bt:condition-wait recv-ok lock)
                             (decf readers-waiting))
            :else :do (return-from recv (values nil nil)))

      (multiple-value-prog1
          (values (dequeue queue) channel)
        (when (> writers-waiting 0)
          (bt:condition-notify send-ok))
        ))))