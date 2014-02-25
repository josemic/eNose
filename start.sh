#!/bin/sh
echo $@
echo $1
# use erl option "+W i / w" to e.g. set the warning level to info / warning
erl -sname enose_$1 -setcookie myCookie -boot start_sasl -pa $PWD/examples/ebin $PWD/rule/ebin $PWD/deps/*/ebin $PWD/content_app/ebin $PWD/stream_app/ebin $PWD/epcap_port_app/ebin -s s12 s $1 -s lager -config app.config

