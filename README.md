

# Cl-Chan


## Usage

`cl-chan` provides a golang-like channel stuff. It provides two types channel: `unbuffered-channel` and `buffered-channel`. 

    ;; make a unbuffered channel
    CL-CHAN> (defvar *c1* (make-channel))
    *C1*
    
    
    ;; make a buffered channel with size 2.
    CL-CHAN> (defvar *c2* (make-channel :buffered t :size 2))
    *C2*

You can use `send` to send value to a channel or `recv` to receive value from it.

    ;; return value is channel itself
    CL-CHAN> (send *c2* 1)
    #<BUFFERED-CHANNEL {100285CD33}>
    
    ;; first return value is value received from channel
    ;; second return value is channel itself
    CL-CHAN> (recv *c2*)
    1
    #<BUFFERED-CHANNEL {100285CD33}>

Also there is a `select` which could be used to wait one of multi channels events to happen.

    
    (select
       ((recv c d)
        (format t "got ~a from c~%" d))
       ((send e val)
        (print "sent val on e~%"))
       ((recv *lots-of-channels* value channel)
        (format t "Got ~A from ~C~%" value channel))
       (otherwise
        (print "would have blocked~%")))

Note, This project is currerently a prototype which I steal many ideas from [chanl](https://github.com/zkat/chanl) and [chan](https://github.com/tylertreat/chan).

However, in project chanl, I found the unbuffered channel may cause race condition which is not fixed ([issue](https://github.com/zkat/chanl/issues/13)).

In project chan, I found the select implenmentation may have a problem ([issue](https://github.com/tylertreat/chan/issues/26)).

Basically, this version of channel implenmentation is almost same as project chan one. So the select may have problem also.

I will try fix it in a while which may introduce a blockp paramter to recv/send.


## Installation

Download the repo in where your quicklisp can find (such as `~/quicklisp/local-projects`), then use `(ql:quickload :cl-chan)` to install.


## Author

-   Nisen (imnisen@gmail.com)


## Copyright/License

Do whatever you want.

