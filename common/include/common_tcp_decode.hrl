%%%-------------------------------------------------------------------
%%% @author michael <michael@donald-desktop>
%%% @copyright (C) 2014, michael
%%% @doc
%%%
%%% @end
%%% Created : 16 Mar 2014 by michael <michael@donald-desktop>
%%%-------------------------------------------------------------------
%% this is only used for decoding broken TCP data (manually)

-record(tcp_robust, {
        sport = 0, dport = 0,
        seqno = 0,
        ackno = 0,
        off = 5, reserved = 0, cwr = 0, ece = 0, urg = 0, ack = 0,
        psh = 0, rst = 0, syn = 0, fin = 0, win = 0,
        sum = 0, urp = 0,
        opt = <<>>
    }).
