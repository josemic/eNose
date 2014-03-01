#!/bin/sh
# e.g. run:
#  to start first observer:
# ./observer 1
#  to start second observer:
# ./observer 2
# etc. 
erl -sname observer$1 -hidden -setcookie myCookie -run observer
