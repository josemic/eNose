#!/bin/sh
echo $@
erl +W i -sname enose$1 -setcookie MyCookie -boot start_sasl -pa $PWD/examples/ebin $PWD/rule/ebin $PWD/deps/*/ebin $PWD/content_app/ebin $PWD/defrag_app/ebin $PWD/epcap_port_app/ebin -run s12_PF_RING_cluster s $1

