(defpackage :cl-chan
  (:use :cl)
  (:import-from :bordeaux-threads :*default-special-bindings*)
  (:export
   #:send
   #:recv
   #:unbuffered-channel
   #:buffered-channel
   #:channel-bufferedp
   #:select
   #:pexec))
