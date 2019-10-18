(in-package :cl-chan)

;;;
;;; Abstract channel
;;;
(defclass abstract-channel ()
  ()
  (:documentation "The base class of all channel"))

(defgeneric send (channel value &key)
  (:documentation "Send value to channel"))

(defgeneric recv (channel &key)
  (:documentation "Receive value from channel"))

(defgeneric channelp (channel)
  (:method ((channel abstract-channel)) t)
  (:method ((something-else t)) nil)
  (:documentation "Check if it is a channel"))


;;;
;;; Unbuffered channels
;;;
(defvar *secret-unbound-value* (gensym "SECRETLY-UNBOUND-")
  "This value is used as a sentinel in channels.")

;; (defclass unbuffered-channel (abstract-channel)
;;   ((value :initform *secret-unbound-value* :accessor channel-value)

;;    (reader-lock :initform (bt:make-recursive-lock) :accessor channel-reader-lock)
;;    (writer-lock :initform (bt:make-recursive-lock) :accessor channel-writer-lock)

;;    (lock :initform (bt:make-recursive-lock) :accessor channel-lock)

;;    (send-ok :initform (bt:make-condition-variable) :accessor channel-send-ok)
;;    (recv-ok :initform (bt:make-condition-variable) :accessor channel-recv-ok)

;;    (readers-waiting :initform 0 :accessor channel-readers-waiting)
;;    (writers-waiting :initform 0 :accessor channel-writers-waiting)))


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

;;; Send value to unbuffered channel.
;; (defmethod send ((channel unbuffered-channel) value &key (blockp t))
;;   (with-accessors ((lock channel-lock)
;;                    (writer-lock channel-writer-lock)
;;                    (recv-ok channel-recv-ok)
;;                    (send-ok channel-send-ok)
;;                    (writers-waiting channel-writers-waiting)
;;                    (readers-waiting channel-readers-waiting))
;;       channel
;;     (bt:with-recursive-lock-held (writer-lock)
;;       (bt:with-recursive-lock-held (lock)
;;         ;; set value
;;         (setf (channel-value channel) value)

;;         ;; may coroperate with recv-ok to active the recver.
;;         (incf writers-waiting)

;;         ;; notify if there are readers waiting
;;         (when (> readers-waiting 0)
;;           (bt:condition-notify recv-ok))

;;         ;; wait signal from readers
;;         (bt:condition-wait send-ok lock)
;;         channel))))


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

;;; Receive value from unbuffered channel
;; (defmethod recv ((channel unbuffered-channel) &key (blockp t))
;;   (with-accessors ((lock channel-lock)
;;                    (reader-lock channel-reader-lock)
;;                    (recv-ok channel-recv-ok)
;;                    (send-ok channel-send-ok)
;;                    (writers-waiting channel-writers-waiting)
;;                    (readers-waiting channel-readers-waiting))
;;       channel
;;     (bt:with-recursive-lock-held (reader-lock)
;;       (bt:with-recursive-lock-held (lock)
;;         ;; wait until senders ok
;;         (loop until (> writers-waiting 0)
;;               do (progn
;;                    (incf readers-waiting)
;;                    (bt:condition-wait recv-ok lock)
;;                    (decf readers-waiting)))

;;         (multiple-value-prog1
;;             ;; get value
;;             (values (shiftf (channel-value channel) *secret-unbound-value*) channel)

;;           ;; decf writers waiting
;;           (decf writers-waiting)

;;           ;; nofity writers to finish
;;           (bt:condition-notify send-ok))))))


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

;; TODO
;; 目前的问题就是， recv发送other-recv-ok时，sender可能没完成
;; 所以第二个 recver就会直接去拿取前一个sender的内容。
;; Solved by mv writers-waiting from send to recv

;;;
;;; Buffered channels (bounded)
;;;
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

;;; Send value to buffered channel.
;; (defmethod send ((channel buffered-channel) value &key (blockp t))
;;   (with-accessors ((lock channel-lock)
;;                    (queue channel-queue)
;;                    (writers-waiting channel-writers-waiting)
;;                    (readers-waiting channel-readers-waiting)
;;                    (recv-ok channel-recv-ok)
;;                    (send-ok channel-send-ok))
;;       channel
;;     (bt:with-recursive-lock-held (lock)
;;       ;; if the queue is full, block until something is removed
;;       (loop while (queue-full-p queue)
;;             do (progn
;;                  (incf writers-waiting)
;;                  (bt:condition-wait send-ok lock)
;;                  (decf writers-waiting)))
;;       (enqueue value queue)
;;       (when (> readers-waiting 0)
;;         (bt:condition-notify recv-ok))
;;       channel)))

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

;; ;;;
;; ;;; select
;; ;;;
;; (defmacro select (&body clauses)
;;   (let ((default))
;;     (with-gensyms (can choosen)
;;       `(let ((,can nil))
;;          ,@(loop :for each :in clauses
;;                  :collect (ecase (clause-type each)
;;                             (:send `(when (chan-can-send ,(second (first each)))
;;                                       (push
;;                                        ',(if (null (fourth (first each)))
;;                                              `(progn
;;                                                 (send ,(second (first each)) ,(third (first each)))
;;                                                 ,@(rest each))
;;                                              `(let ((,(fourth (first each))
;;                                                       (send ,(second (first each)) ,(third (first each)))))
;;                                                 ,@(rest each))
;;                                              )
;;                                        ,can)))
;;                             (:recv `(when (chan-can-recv ,(second (first each)))
;;                                       (push '(multiple-value-bind (,@(cddr (first each)))
;;                                               (recv ,(second (first each)))
;;                                               ,@(rest each))
;;                                             ,can)))
;;                             (:else (push (rest each) default) nil)))
;;          (if (null ,can)
;;              (progn
;;                ,@(pop default))
;;              (progn
;;                (let* ((,choosen (list-random-element ,can)))
;;                  (eval ,choosen))))))))


;; (defgeneric chan-can-recv (channel)
;;   (:method ((channel unbuffered-channel))
;;     (bt:with-recursive-lock-held ((channel-lock channel))
;;       (> (channel-writers-waiting channel) 0)))
;;   (:method ((channel buffered-channel))
;;     (> (queue-count (channel-queue channel)) 0)))

;; (defgeneric chan-can-send (channel)
;;   (:method ((channel unbuffered-channel))
;;     (bt:with-recursive-lock-held ((channel-lock channel))
;;       (> (channel-readers-waiting channel) 0)))
;;   (:method ((channel buffered-channel))
;;     (let ((queue (channel-queue channel)))
;;       (< (queue-count queue) (queue-length queue)))))

;; (defgeneric chan-size (channel)
;;   (:method ((channel unbuffered-channel)) 0)
;;   (:method ((channel buffered-channel))
;;     (bt:with-recursive-lock-held ((channel-lock channel))
;;       (queue-count (channel-queue channel)))))

;; (defun clause-type (clause)
;;   (cond ((when (symbolp (car clause))
;;            (or (string-equal (car clause) "t")
;;                (string-equal (car clause) "else")
;;                (string-equal (car clause) "otherwise")))
;;          :else) ;; when `default case` use "t","else","otherwise",  we mark it ":else"
;;         ((atom (car clause)) (error "Invalid selector: ~S" (car clause))) ;; clause could't be `atom`
;;         ((string-equal (caar clause) "send") :send)
;;         ((string-equal (caar clause) "recv") :recv)
;;         (t (error "Invalid selector: ~S" (caar clause)))))


;;; The new intance method
;; TODO make this check size at macro expansion.
(defun make-channel (&key (buffered nil) (size 1))
  (if buffered
      (make-instance 'buffered-channel :size size)
      (make-instance 'unbuffered-channel)))


