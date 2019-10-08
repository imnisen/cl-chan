
# Table of Contents

1.  [Cl-Chan](#orge323517)
    1.  [Usage](#orgeef8161)
    2.  [Installation](#orge92259b)
    3.  [Author](#org3274cd6)
    4.  [Copyright](#orgbf5a59b)
    5.  [License](#orga597088)
    6.  [S](#org2e79794)
        1.  [add buffered channel](#org90f2e61)
        2.  [add select](#orgf3952c0)
        3.  [may select has a bug, first can recv/send, then recv/send it fails. so we should retry right?](#org985cf3f)
        4.  [port other chanl rest concepts](#orge87a636)
        5.  [port chan.c other funcs](#org8eb90b7)
        6.  [write test case](#org08bb7c4)
        7.  [refactor readers,writers to readers-waiting, writers-waiting](#orgceee772)
        8.  [select implenmentation use \`eval\`, consider trying another method to avoid it?](#org82bcd2e)


<a id="orge323517"></a>

# Cl-Chan


<a id="orgeef8161"></a>

## Usage


<a id="orge92259b"></a>

## Installation


<a id="org3274cd6"></a>

## Author

-   Nisen (imnisen@gmail.com)


<a id="orgbf5a59b"></a>

## Copyright

Copyright (c) 2019 Nisen (imnisen@gmail.com)


<a id="orga597088"></a>

## License

Licensed under the BSD License.


<a id="org2e79794"></a>

## TODO S


<a id="org90f2e61"></a>

### DONE add buffered channel

-   check how the queue is make?


<a id="orgf3952c0"></a>

### DONE add select


<a id="org985cf3f"></a>

### may select has a bug, first can recv/send, then recv/send it fails. so we should retry right?


<a id="orge87a636"></a>

### port other chanl rest concepts


<a id="org8eb90b7"></a>

### port chan.c other funcs


<a id="org08bb7c4"></a>

### write test case


<a id="orgceee772"></a>

### refactor readers,writers to readers-waiting, writers-waiting


<a id="org82bcd2e"></a>

### select implenmentation use \`eval\`, consider trying another method to avoid it?

