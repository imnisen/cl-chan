;;;
;;; Unbuffered channels
;;;

(in-package :cl-chan)

(defvar *secret-unbound-value* (gensym "SECRETLY-UNBOUND-")
  "This value is used as a sentinel in channels.")

(defclass unbuffered-channel (abstract-channel)
  ((value :initform *secret-unbound-value* :accessor channel-value)

   (reader-lock :initform (bt:make-recursive-lock) :accessor channel-reader-lock)
   (writer-lock :initform (bt:make-recursive-lock) :accessor channel-writer-lock)

   (lock :initform (bt:make-recursive-lock) :accessor channel-lock)

   (send-ok :initform (bt:make-condition-variable) :accessor channel-send-ok)
   (recv-ok :initform (bt:make-condition-variable) :accessor channel-recv-ok)

   (readers-waiting :initform 0 :accessor channel-readers-waiting)
   (writers-waiting :initform 0 :accessor channel-writers-waiting)

   (recvers :initform 0 :accessor channel-recvers)
   (senders :initform 0 :accessor channel-senders)

   (other-send-ok :initform (bt:make-condition-variable) :accessor channel-other-send-ok)
   (other-recv-ok :initform (bt:make-condition-variable) :accessor channel-other-recv-ok)))

(defmethod send ((channel unbuffered-channel) value &key (blockp t))
  (with-accessors ((write-lock channel-writer-lock)
                   (senders channel-senders)
                   (other-send-ok channel-other-send-ok)
                   (lock channel-lock)
                   (readers-waiting channel-readers-waiting)
                   (writers-waiting channel-writers-waiting)
                   (send-ok channel-send-ok)
                   (recv-ok channel-recv-ok))
      channel

    (bt:with-lock-held (write-lock)
      (loop :while (> senders 0)
            :if blockp :do (progn
                             (format t "senders:waiting other-send-ok..~%")
                             (bt:condition-wait other-send-ok write-lock)
                             (format t "senders:wake from waiting of other-send-ok~%"))
            :else :do (return-from send nil))
      (incf senders))

    (bt:with-lock-held (lock)
      (if (= readers-waiting 0)
          (if blockp
              (progn
                (setf (channel-value channel) value)
                (incf writers-waiting)

                (format t "senders:waiting for send-ok~%")
                (bt:condition-wait send-ok lock)
                (format t "senders:wake from waiting of send-ok~%")

                ;; (decf writers-waiting)
                )
              (progn
                (bt:with-lock-held (write-lock)
                  (decf senders))
                (return-from send nil)))
          (progn
            (setf (channel-value channel) value)
            (incf writers-waiting)

            (format t "senders:notify recv-ok ~%")
            (bt:condition-notify recv-ok)
            (format t "senders:waiting send-ok~%")

            (bt:condition-wait send-ok lock)
            (format t "senders:wake from waiting of send-ok~%")

            ;; (decf writers-waiting)
            )))

    (bt:with-lock-held (write-lock)
      (decf senders)

      (format t "senders:notify other-send-ok~%")
      (bt:condition-notify other-send-ok) ;; TODO this also signal when no other senders
      )
    channel
    ))

    (defmethod recv ((channel unbuffered-channel) &key (blockp t))
  (with-accessors ((reader-lock channel-reader-lock)
                   (recvers channel-recvers)
                   (other-recv-ok channel-other-recv-ok)
                   (lock channel-lock)
                   (writers-waiting channel-writers-waiting)
                   (readers-waiting channel-readers-waiting)
                   (recv-ok channel-recv-ok)
                   (send-ok channel-send-ok))
      channel
    (let ((value))
      (bt:with-lock-held (reader-lock)
        (loop :while (> recvers 0)
              :if blockp :do (progn
                               (format t "recver:waiting other-recv-ok~%")
                               (bt:condition-wait other-recv-ok reader-lock)
                               (format t "recver:wake from waiting of other-recv-ok~%"))
              :else :do (return-from recv (values nil nil)))
        (incf recvers))

      (bt:with-lock-held (lock)
        (loop :while (= writers-waiting 0)
              :if blockp
              :do (progn
                    (incf readers-waiting)
                    (format t "recver:waiting recv-ok~%")
                    (bt:condition-wait recv-ok lock)
                    (format t "recver:wake from waiting of recv-ok~%")
                    (decf readers-waiting))
              :else :do (progn
                          ;; protect with lock
                          (bt:with-lock-held (reader-lock)
                            (decf recvers))
                          (return-from recv (values nil nil))))
        (setf value
              (shiftf (channel-value channel) *secret-unbound-value*))

        (decf writers-waiting)  ;; Move (decf writers-waiting) from senders to recvs, it is important. If not, deadlock!

        (format t "recver:notify send-ok~%")
        (bt:condition-notify send-ok)
        )

      (bt:with-lock-held (reader-lock)
        (decf recvers)

        (format t "recver:notify other-recv-ok~%")
        (bt:condition-notify other-recv-ok) ;; This would cause racing, if
        )

      (values value channel))))
