(defpackage cl-chan
  (:use :cl)
  (:import-from :bordeaux-threads :*default-special-bindings*)
  (:export
   #:channel
   #:buffered-channel
   #:send
   #:recv))
