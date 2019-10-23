;;;
;;; Unbuffered channels
;;;

(in-package :cl-chan)

(defvar *secret-unbound-value* (gensym "SECRETLY-UNBOUND-")
  "This value is used as a sentinel in channels.")

(defclass unbuffered-channel (abstract-channel)
  ((value :initform *secret-unbound-value* :accessor channel-value)

   ;;; protect sender and recver
   (lock :initform (bt:make-lock) :accessor channel-lock) ;; protect sender and recver access value
   (recvers-waiting :initform 0 :accessor channel-recvers-waiting) ;; how many recvers waiting for sender (this case should be 0 or 1)
   (senders-waiting :initform 0 :accessor channel-senders-waiting) ;; how many senders waiting for recver (this case should be 0 or 1)
   (send-ok :initform (bt:make-condition-variable) :accessor channel-send-ok) ;; recver notify sender
   (recv-ok :initform (bt:make-condition-variable) :accessor channel-recv-ok) ;; sender nofity recver

   ;;; protect sender and sender, recver and recver
   (send-lock :initform (bt:make-lock) :accessor channel-send-lock) ;; separate multi senders
   (recv-lock :initform (bt:make-lock) :accessor channel-recv-lock) ;; separate multi recvers
   (recvers :initform 0 :accessor channel-recvers) ;; how many recvers waiting for the working recver to finish.
   (senders :initform 0 :accessor channel-senders) ;; how many senders waiting for the working sender to finish.
   (other-send-ok :initform (bt:make-condition-variable) :accessor channel-other-send-ok)
   (other-recv-ok :initform (bt:make-condition-variable) :accessor channel-other-recv-ok)))

(defmethod send ((channel unbuffered-channel) value &key (blockp t))
  (with-accessors ((recv-lock channel-recv-lock)
                   (senders channel-senders)
                   (other-send-ok channel-other-send-ok)
                   (lock channel-lock)
                   (recvers-waiting channel-recvers-waiting)
                   (senders-waiting channel-senders-waiting)
                   (send-ok channel-send-ok)
                   (recv-ok channel-recv-ok))
      channel
    (bt:with-lock-held (recv-lock)
      (loop :while (> senders 0)
            :if blockp :do (bt:condition-wait other-send-ok recv-lock)
            :else :do (return-from send nil))
      (incf senders))

    (bt:with-lock-held (lock)
      (if (= recvers-waiting 0)
          (if blockp
              (progn
                (setf (channel-value channel) value)
                (incf senders-waiting)
                (bt:condition-wait send-ok lock))
              (progn
                (bt:with-lock-held (recv-lock)
                  (decf senders))
                (return-from send nil)))
          (progn
            (setf (channel-value channel) value)
            (incf senders-waiting)
            (bt:condition-notify recv-ok)
            (bt:condition-wait send-ok lock)
            )))

    (bt:with-lock-held (recv-lock)
      (decf senders)
      (bt:condition-notify other-send-ok) ;; TODO this also signal when no other senders
      )

    channel))

(defmethod recv ((channel unbuffered-channel) &key (blockp t))
  (with-accessors ((send-lock channel-send-lock)
                   (recvers channel-recvers)
                   (other-recv-ok channel-other-recv-ok)
                   (lock channel-lock)
                   (senders-waiting channel-senders-waiting)
                   (recvers-waiting channel-recvers-waiting)
                   (recv-ok channel-recv-ok)
                   (send-ok channel-send-ok))
      channel
    (let ((value))
      (bt:with-lock-held (send-lock)
        (loop :while (> recvers 0)
              :if blockp :do (bt:condition-wait other-recv-ok send-lock)
              :else :do (return-from recv (values nil nil)))
        (incf recvers))

      (bt:with-lock-held (lock)
        (loop :while (= senders-waiting 0)
              :if blockp
              :do (progn
                    (incf recvers-waiting)
                    (bt:condition-wait recv-ok lock)
                    (decf recvers-waiting))
              :else :do (progn
                          (bt:with-lock-held (send-lock)
                            (decf recvers))
                          (return-from recv (values nil nil))))
        (setf value
              (shiftf (channel-value channel) *secret-unbound-value*))
        (decf senders-waiting)  ;; Move (decf senders-waiting) from senders to recvs, it is important. If not, deadlock!
        (bt:condition-notify send-ok))

      (bt:with-lock-held (send-lock)
        (decf recvers)
        (bt:condition-notify other-recv-ok) ;; TODO this also signal when no other senders
        )

      (values value channel))))
