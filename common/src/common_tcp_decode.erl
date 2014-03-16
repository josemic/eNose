%%%-------------------------------------------------------------------
%%% @author michael <michael@donald-desktop>
%%% @copyright (C) 2014, michael
%%% @doc
%%%
%%% @end
%%% Created : 16 Mar 2014 by michael <michael@donald-desktop>
%%%-------------------------------------------------------------------
-module(common_tcp_decode).
-export([codec/1]).

-include("../include/common_tcp_decode.hrl").

%% this is only used for decoding broken TCP data (manually)

codec(
    <<SPort:16, DPort:16,
      SeqNo:32,
      AckNo:32,
      Off:4, Reserved:4, CWR:1, ECE:1, URG:1, ACK:1,
      PSH:1, RST:1, SYN:1, FIN:1, Win:16,
      Sum:16, Urp:16,
      Rest/binary>>
) when Off >= 5 ->
    OptLen = (Off - 5) * 4,
    <<Opt:OptLen/binary, Payload/binary>> = Rest,
    {#tcp_robust{
        sport = SPort, dport = DPort,
        seqno = SeqNo,
        ackno = AckNo,
        off = Off, reserved = Reserved, cwr = CWR, ece = ECE, urg = URG, ack = ACK,
        psh = PSH, rst = RST, syn = SYN, fin = FIN, win = Win,
        sum = Sum, urp = Urp,
        opt = Opt
    }, Payload}.
