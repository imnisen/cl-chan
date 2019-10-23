

# Cl-Chan


## Description

`cl-chan` provides a golang like unbuffered/buffered channel.

With `send` or `recv`, you can send or receive value to channel.

Also with `select`, you can randomly listen to event from a channel.

It based on multi-threads library `bordeaux-threads` to act like gorotine stuff.

Note, 

This project is inspired by [chanl](https://github.com/zkat/chanl) and [chan](https://github.com/tylertreat/chan). Lots of utils code is copy from  [chanl](https://github.com/zkat/chanl), such as `queues.lisp`, `threads.lisp`, `utils.lisp`.

The reason I write `cl-chan` is that as the only useable CSP lib I find in cl world,  [chanl](https://github.com/zkat/chanl) test cases may cause race condition, you can refer to this [issue](https://github.com/zkat/chanl/issues/13). 
It seems hard to fix it as it abstracts a lot from different channels. So I made a simple worked one.

I refer to project [chan](https://github.com/tylertreat/chan). But I found the select implenmentation may have a problem ([issue](https://github.com/tylertreat/chan/issues/26)), So I chose the select the implementation of [chanl](https://github.com/zkat/chanl) .
Also, in order to add functionality of non-block send and receive, I rewrite the logic of `send` and `recv`.


## Usage

`cl-chan` provides two types channel: `unbuffered-channel` and `buffered-channel`. 

    ;; make a unbuffered channel
    CL-CHAN> (defvar *c1* (make-instance 'unbuffered-channel))
    *C1*
    
    
    ;; make a buffered channel with size 2.
    CL-CHAN> (defvar *c2* (make-instance 'buffered-channel :size 2))
    *C2*
    
    ;; check if channel is buffered
    CL-CHAN> (channel-bufferedp *c1*)
    NIL
    
    CL-CHAN> (channel-bufferedp *c2*)
    T

You can use `send` to send value to a channel or `recv` to receive value from it.

    ;; return value is channel itself
    CL-CHAN> (send *c2* 1)
    #<BUFFERED-CHANNEL {100285CD33}>
    
    ;; first return value is value received from channel
    ;; second return value is channel itself
    CL-CHAN> (recv *c2*)
    1
    #<BUFFERED-CHANNEL {100285CD33}>
    
    ;; send and receive with blockp nil
    CL-CHAN> (send *c2* :blockp nil)
    #<BUFFERED-CHANNEL {100285CD33}>
    
    CL-CHAN> (recv *c2* :blockp nil)
    1
    #<BUFFERED-CHANNEL {100285CD33}>

Also there is a `select` which could be used to wait one of multi channels events to happen.

If there is no default case, the `select` statement blocks until at least one of the communications can proceed. (The select will keep looping, which is not good. Need to fix.)

The difference to golang select is select an empty expression. Golang select will block forever however, our's will return nil. (This may change overtime, don't rely on it.)

    
    (select
       ((recv c d)
        (format t "got ~a from c~%" d))
       ((send e val)
        (print "sent val on e~%"))
       ((recv *lots-of-channels* value channel)
        (format t "Got ~A from ~C~%" value channel))
       (otherwise
        (print "would have blocked~%")))

Create a new thread continually reading values and printing them:

    (pexec ()
       (loop (format t "~a~%" (recv *c*))))

Create a new thread that runs a function:

    (pcall #'my-function)


## Installation

Download the repo in where your quicklisp can find (such as `~/quicklisp/local-projects`), then use `(ql:quickload :cl-chan)` to load.

Currently tested on sbcl and ccl, you can test as: `(asdf:test-system :cl-chan)`


## Author

-   Nisen (imnisen@gmail.com)


## Copyright/License

Do whatever you want.

