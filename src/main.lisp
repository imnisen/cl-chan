(in-package :cl-chan)

;;;
;;; Abstract channel
;;;
(defclass abstract-channel () ())

(defgeneric send (chan value)
  (:documentation "TODO"))

(defgeneric recv (chan)
  (:documentation "TODO"))


;;;
;;; Unbuffered channels
;;;
(defvar *secret-unbound-value* (gensym "SECRETLY-UNBOUND-")
  "This value is used as a sentinel in channels.")

(defclass channel (abstract-channel)
  ((value :initform *secret-unbound-value* :accessor channel-value)
   (reader-lock :initform (bt:make-recursive-lock) :accessor channel-reader-lock)
   (writer-lock :initform (bt:make-recursive-lock) :accessor channel-writer-lock)
   (lock :initform (bt:make-recursive-lock) :accessor channel-lock)
   (send-ok :initform (bt:make-condition-variable) :accessor channel-send-ok)
   (recv-ok :initform (bt:make-condition-variable) :accessor channel-recv-ok)
   (readers :initform 0 :accessor channel-readers)
   (writers :initform 0 :accessor channel-writers)

   ;; need closed? add latter!

   )
  (:documentation "TODO"))

;; set channel value
(defgeneric channel-insert-value (channel value)
  (:method ((channel channel) value)
    (setf (channel-value channel) value)))

;; get channel value
(defgeneric channel-grab-value (channel)
  (:method ((channel channel))
    (shiftf (channel-value channel) *secret-unbound-value*)))

(defmethod send ((channel channel) value)
  (with-accessors ((lock channel-lock)
                   (writer-lock channel-writer-lock)
                   (recv-ok channel-recv-ok)
                   (send-ok channel-send-ok)
                   (writers channel-writers)
                   (readers channel-readers))
      channel
    (bt:with-recursive-lock-held (writer-lock)
      (bt:with-recursive-lock-held (lock) ;; ========== lock
        (format t "send: start~%")
        (channel-insert-value channel value)
        (format t "send: insert value~%")
        (incf writers)

        (when (> readers 0)
          (bt:condition-notify recv-ok) ;; ----- notify reck-ok
          (format t "send: notify recv-ok~%"))

        (format t "send: wait send-ok~%")
        (bt:condition-wait send-ok lock) ;; ========== release lock , wait send-ok
        (format t "send:get send-ok~%")
        (format t "send:end~%")


        channel))))

(defmethod recv ((channel channel))
  (with-accessors ((lock channel-lock)
                   (reader-lock channel-reader-lock)
                   (recv-ok channel-recv-ok)
                   (send-ok channel-send-ok)
                   (writers channel-writers)
                   (readers channel-readers))
      channel
    (bt:with-recursive-lock-held (reader-lock)
      (bt:with-recursive-lock-held (lock)  ;; ========= hold lock
        (format t "recv: start~%")
        (loop until (> writers 0)
              do (progn
                   (incf readers)
                   (format t "recv: wait recv-ok ~%")
                   (bt:condition-wait recv-ok lock)  ;;========= release lock,  wait recv-ok
                   (format t "recv: get recv-ok~%")
                   (decf readers)))

        (multiple-value-prog1
            (values (channel-grab-value channel) channel)
          (format t "recv:get value~%")
          (decf writers)
          (bt:condition-notify send-ok) ;; ------ notify send-ok
          (format t "recv: notify send-ok~%")
          (format t "recv end~%"))))))


;;;
;;; Buffered channels (bounded)
;;;
(defclass buffered-channel (abstract-channel)
  ((queue :accessor channel-queue)

   (lock :initform (bt:make-recursive-lock) :accessor channel-lock)
   (send-ok :initform (bt:make-condition-variable) :accessor channel-send-ok)
   (recv-ok :initform (bt:make-condition-variable) :accessor channel-recv-ok)
   (readers-waiting :initform 0 :accessor channel-readers-waiting)
   (writers-waiting :initform 0 :accessor channel-writers-waiting)

   ;; need closed? add latter!

   )
  (:documentation "TODO"))

(defconstant +maximum-buffer-size+ (- array-total-size-limit 2)
  "The exclusive upper bound on the size of a channel's buffer.")

(defmethod initialize-instance :after ((channel buffered-channel) &key (size 1))
  (assert (typep size `(integer 1 ,(1- +maximum-buffer-size+))) (size)
          "Buffer size must be a non-negative fixnum..")
  (setf (channel-queue channel) (make-queue size)))

(defgeneric channel-buffered-p (channel)
  (:method ((anything-else t)) nil)
  (:method ((channel buffered-channel)) t))


(defmethod send ((channel buffered-channel) value)
  (with-accessors ((lock channel-lock)
                   (queue channel-queue)
                   (writers-waiting channel-writers-waiting)
                   (readers-waiting channel-readers-waiting)
                   (recv-ok channel-recv-ok)
                   (send-ok channel-send-ok))
      channel
    (bt:with-recursive-lock-held (lock)

      ;; if the queue is full, block until something is removed
      (loop while (queue-full-p queue)
            do (progn
                 (incf writers-waiting)
                 (bt:condition-wait send-ok lock)
                 (decf writers-waiting)))

      (enqueue value queue)

      (when (> readers-waiting 0)
        (bt:condition-notify recv-ok))

      channel
      )))

(defmethod recv ((channel buffered-channel))
  (with-accessors ((lock channel-lock)
                   (queue channel-queue)
                   (writers-waiting channel-writers-waiting)
                   (readers-waiting channel-readers-waiting)
                   (recv-ok channel-recv-ok)
                   (send-ok channel-send-ok))
      channel
    (bt:with-recursive-lock-held (lock)

      ;; if the queue is full, block until something is removed
      (loop while (queue-empty-p queue)
            do (progn
                 (incf readers-waiting)
                 (bt:condition-wait recv-ok lock)
                 (decf readers-waiting)))

      (multiple-value-prog1
          (values (dequeue queue) channel)
        (when (> writers-waiting 0)
          (bt:condition-notify send-ok))
        ))))
