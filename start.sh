#!/bin/sh
erl +W i -sname enose -setcookie MyCookie $@ -boot start_sasl -pa $PWD/examples/ebin $PWD/rule/ebin $PWD/deps/*/ebin $PWD/content_app/ebin $PWD/defrag_app/ebin $PWD/epcap_port_app/ebin

