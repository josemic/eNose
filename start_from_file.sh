#!/bin/sh
echo $@
echo $1
erl -sname enose -setcookie myCookie -boot start_sasl -pa $PWD/examples/ebin $PWD/rule/ebin $PWD/deps/*/ebin $PWD/content_app/ebin $PWD/stream_app/ebin $PWD/epcap_port_app/ebin $PWD/common/ebin -s fromfile s $1 -s lager -config app.config

