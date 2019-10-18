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
