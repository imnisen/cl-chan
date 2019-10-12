(in-package :cl-chan)

;;;
;;; Abstract channel
;;;
(defclass abstract-channel ()
  ()
  (:documentation "The base class of all channel"))

(defgeneric send (channel value)
  (:documentation "Send value to channel"))

(defgeneric recv (channel)
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

(defclass unbuffered-channel (abstract-channel)
  ((value :initform *secret-unbound-value* :accessor channel-value)
   (reader-lock :initform (bt:make-recursive-lock) :accessor channel-reader-lock)
   (writer-lock :initform (bt:make-recursive-lock) :accessor channel-writer-lock)
   (lock :initform (bt:make-recursive-lock) :accessor channel-lock)
   (send-ok :initform (bt:make-condition-variable) :accessor channel-send-ok)
   (recv-ok :initform (bt:make-condition-variable) :accessor channel-recv-ok)
   (readers-waiting :initform 0 :accessor channel-readers-waiting)
   (writers-waiting :initform 0 :accessor channel-writers-waiting)))

;;; Send value to unbuffered channel.
(defmethod send ((channel unbuffered-channel) value)
  (with-accessors ((lock channel-lock)
                   (writer-lock channel-writer-lock)
                   (recv-ok channel-recv-ok)
                   (send-ok channel-send-ok)
                   (writers-waiting channel-writers-waiting)
                   (readers-waiting channel-readers-waiting))
      channel
    (bt:with-recursive-lock-held (writer-lock)
      (bt:with-recursive-lock-held (lock)
        (setf (channel-value channel) value)
        (incf writers-waiting)
        (when (> readers-waiting 0)
          (bt:condition-notify recv-ok)
          (bt:condition-wait send-ok lock))
        channel))))

;;; Receive value from unbuffered channel
(defmethod recv ((channel unbuffered-channel))
  (with-accessors ((lock channel-lock)
                   (reader-lock channel-reader-lock)
                   (recv-ok channel-recv-ok)
                   (send-ok channel-send-ok)
                   (writers-waiting channel-writers-waiting)
                   (readers-waiting channel-readers-waiting))
      channel
    (bt:with-recursive-lock-held (reader-lock)
      (bt:with-recursive-lock-held (lock)
        (loop until (> writers-waiting 0)
              do (progn
                   (incf readers-waiting)
                   (bt:condition-wait recv-ok lock)
                   (decf readers-waiting)))
        (multiple-value-prog1
            (values (shiftf (channel-value channel) *secret-unbound-value*) channel)
          (decf writers-waiting)
          (bt:condition-notify send-ok))))))


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
      channel)))

;;; Receive value from buffered channel
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

;;;
;;; select
;;;
(defmacro select (&body clauses)
  (let ((default))
    (with-gensyms (can choosen channel typ clau arg)
      `(let ((,can nil))
         ,@(loop :for each :in clauses
                 :collect (ecase (clause-type each)
                            (:send `(when (chan-can-send ,(second (first each)))
                                      (push (list
                                             ,(second (first each)) ;; channel
                                             :send         ;; type
                                             ',(rest each) ;; body
                                             ,(third (first each))) ;; val to be sent
                                            ,can)))
                            (:recv `(when (chan-can-recv ,(second (first each)))
                                      (push (list
                                             ,(second (first each)) ;; channel
                                             :recv         ;; type
                                             ',(rest each) ;; body
                                             ,(third (first each)) ;; recv variable to bind
                                             )
                                            ,can)))
                            (:else (push (rest each) default) nil)))
         (if (null ,can)
             (progn
               ,@(pop default))
             (progn
               (let* ((,choosen (list-random-element ,can))
                      (,channel (first ,choosen))
                      (,typ (second ,choosen))
                      (,clau (third ,choosen))
                      (,arg (fourth ,choosen)))
                 (if (equal ,typ :recv)
                     (multiple-value-bind (,arg)
                         (recv ,channel)
                       (mapcar #'eval ,clau))
                     (progn (send ,channel ,arg)
                            (mapcar #'eval ,clau))))))
         nil))))


(defgeneric chan-can-recv (channel)
  (:method ((channel unbuffered-channel))
    (bt:with-recursive-lock-held ((channel-lock channel))
      (> (channel-writers-waiting channel) 0)))
  (:method ((channel buffered-channel))
    (> (queue-count (channel-queue channel)) 0)))

(defgeneric chan-can-send (channel)
  (:method ((channel unbuffered-channel))
    (bt:with-recursive-lock-held ((channel-lock channel))
      (> (channel-writers-waiting channel) 0)))
  (:method ((channel buffered-channel))
    (let ((queue (channel-queue channel)))
      (< (queue-count queue) (queue-length queue)))))

(defgeneric chan-size (channel)
  (:method ((channel unbuffered-channel)) 0)
  (:method ((channel buffered-channel))
    (bt:with-recursive-lock-held ((channel-lock channel))
      (queue-count (channel-queue channel)))))

(defun clause-type (clause)
  (cond ((when (symbolp (car clause))
           (or (string-equal (car clause) "t")
               (string-equal (car clause) "else")
               (string-equal (car clause) "otherwise")))
         :else) ;; when `default case` use "t","else","otherwise",  we mark it ":else"
        ((atom (car clause)) (error "Invalid selector: ~S" (car clause))) ;; clause could't be `atom`
        ((string-equal (caar clause) "send") :send)
        ((string-equal (caar clause) "recv") :recv)
        (t (error "Invalid selector: ~S" (caar clause)))))


;;; The new intance method
(defun make-channel (&key (buffered nil) (size 1))
  (if buffered
      (make-instance 'buffered-channel :size size)
      (make-instance 'unbuffered-channel)))
