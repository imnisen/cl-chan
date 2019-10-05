;;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Base: 10; indent-tabs-mode: nil -*-
;;;;
;;;; Copyright © 2009 Kat Marchan, Adlai Chandrasekhar
;;;;
;;;; Utilities
;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(in-package :cl-chan)

(defun ensure-list (x)
  (if (listp x) x
      (list x)))

(defun unzip-alist (alist)
  "Returns two fresh lists containing the keys and values of ALIST"
  (loop for pair in alist
     collect (first  pair) into keys
     collect (second pair) into vals
     finally (return (values keys vals))))

(defun nunzip-alist (alist &aux (keys alist) (vals (car alist)))
  "Destructive, non-consing version of `unzip-alist'."
  (do (
       ;; Pointers to the list tails, so we can push to their ends
       (keys-tail keys (cdr keys-tail))
       (vals-tail vals (cdr vals-tail))

       ;; And pointers to the elements that we pick out at each stage
       (next-key (caar alist) (caar alist))
       (next-val (cdar alist) (cdar alist)))

      ;; We're done when the tails are empty
      ((null keys-tail)
       (values keys vals))

    ;; Since we already have pointers to the elements of this stage, and
    ;; to the relevant list tails, we just need to hang on to the remainder
    ;; of the original alist -- a pointer which is lost at the next stage.
    (setf alist (cdr alist))

    ;; Scalpel please.
    (setf (car keys-tail) next-key       ; Must... not... use... RPLACA!
          (car vals-tail) next-val       ; Must... resist... the urge...
          (cdr vals-tail) (car alist)))) ; Gaaaah!

(defmacro fun (&body body)
  "This macro puts the FUN back in FUNCTION."
  `(lambda (&optional _) (declare (ignorable _)) ,@body))

(defmacro econd (&body cond-clauses &aux error)
  "Like `ecase', but for `cond'. An optional initial string is used as the error message."
  (when (stringp (car cond-clauses))
    (setf error (pop cond-clauses)))
  `(cond ,@cond-clauses
         (t (error ,(or error "None of the ECOND clauses matched.")))))

(defmacro with-gensyms (names &body body)
  `(let ,(mapcar (fun `(,_ (gensym ,(string _)))) names)
     ,@body))

(defmacro pop-declarations (place)
  "Returns and removes all leading declarations from PLACE, which should be
a setf-able form. NOTE: Does not support docstrings."
  (with-gensyms (form)
    `(loop for ,form in ,place
        while (handler-case (string-equal (car ,form) 'declare) (type-error ()))
        collect (pop ,place))))

(defmacro aif (test then &optional else)
  `(let ((it ,test))
     (if it ,then ,else)))

(defmacro when-bind (variable test &body body)
  `(let ((,variable ,test))
     ,@(pop-declarations body)
     (when ,variable ,@body)))

(defmacro awhen (test &body body)
  `(when-bind it ,test ,@body))

(defmacro define-speedy-function (name args &body body)
  `(progn (declaim (inline ,name))
          (defun ,name ,args
            (declare (optimize (speed 3) (safety 0) (debug 0)))
            ,@body)))

(defmacro define-print-object (((object class) &key (identity t) (type t)) &body body)
  (with-gensyms (stream)
    `(defmethod print-object ((,object ,class) ,stream)
      (print-unreadable-object (,object ,stream :type ,type :identity ,identity)
        (let ((*standard-output* ,stream)) ,@body)))))

(defmacro pushend (new-item list list-end &environment env)
  (multiple-value-bind (list.gvars list.vals list.gstorevars list.setter list.getter)
      (get-setf-expansion list env)
    (multiple-value-bind (tail.gvars tail.vals tail.gstorevars tail.setter tail.getter)
	(get-setf-expansion list-end env)
      (let ((gitem (gensym))
	    (list.gstorevar (first list.gstorevars))
	    (tail.gstorevar (first tail.gstorevars)))
	`(let (,@(mapcar #'list list.gvars list.vals)
	       ,@(mapcar #'list tail.gvars tail.vals))
	   (let ((,gitem (list ,new-item)))
	     (if ,list.getter
		 (let ((,tail.gstorevar ,gitem))
		   (setf (cdr ,tail.getter) ,gitem)
		   ,tail.setter)
		 (let ((,list.gstorevar ,gitem)
		       (,tail.gstorevar ,gitem))
		   ,list.setter ,tail.setter))))))))
