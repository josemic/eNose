#!/bin/sh
echo $@
echo $1
erl +W i -sname enose_$1 -setcookie myCookie -boot start_sasl -pa $PWD/examples/ebin $PWD/rule/ebin $PWD/deps/*/ebin $PWD/content_app/ebin $PWD/stream_app/ebin $PWD/epcap_port_app/ebin -s s12 s $1

