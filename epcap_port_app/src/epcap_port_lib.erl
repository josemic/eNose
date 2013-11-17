%% Copyright (c) 2010-2013, Michael Santos <michael.santos@gmail.com>
%% All rights reserved.
%%
%% Redistribution and use in source and binary forms, with or without
%% modification, are permitted provided that the following conditions
%% are met:
%%
%% Redistributions of source code must retain the above copyright
%% notice, this list of conditions and the following disclaimer.
%%
%% Redistributions in binary form must reproduce the above copyright
%% notice, this list of conditions and the following disclaimer in the
%% documentation and/or other materials provided with the distribution.
%%
%% Neither the name of the author nor the names of its contributors
%% may be used to endorse or promote products derived from this software
%% without specific prior written permission.
%%
%% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
%% "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
%% LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
%% FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
%% COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
%% INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
%% BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
%% LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
%% CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
%% LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
%% ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
%% POSSIBILITY OF SUCH DAMAGE.
-module(epcap_port_lib).
-include_lib("pkt/include/pkt.hrl").

-export([decode/3,
	 ether_addr/1, 
	 header/1, 
	 iso_8601_fmt/1,
         packet/2, 
	 timestamp/1,
	 to_ascii/1]).

-define(is_print(C), C >= $ , C =< $~).

%% Taken from sniff example:

decode(DLT, Data, _Crash = true) ->
    pkt:decapsulate({pkt:dlt(DLT), Data});
decode(DLT, Data, _Crash = false) ->
    case pkt:decode(pkt:dlt(DLT), Data) of
        {ok, {Headers, Payload}} ->
            Headers ++ [Payload];
        {error, SoFar, _Failed} ->
            SoFar
    end.

header(Payload) ->
    header(Payload, []).

header([], Acc) ->
    lists:reverse(Acc);
header([#ether{shost = Shost, dhost = Dhost}|Rest], Acc) ->
    header(Rest, [{ether, [{source_macaddr, ether_addr(Shost)},
                    {destination_macaddr, ether_addr(Dhost)}]}|Acc]);
header([#ipv4{saddr = Saddr, daddr = Daddr, p = Proto}|Rest], Acc) ->
    header(Rest, [{ipv4, [{protocol, pkt:proto(Proto)},
                    {source_address, inet_parse:ntoa(Saddr)},
                    {destination_address, inet_parse:ntoa(Daddr)}]}|Acc]);
header([#ipv6{saddr = Saddr, daddr = Daddr, next = Proto}|Rest], Acc) ->
    header(Rest, [{ipv6, [{protocol, pkt:proto(Proto)},
                    {source_address, inet_parse:ntoa(Saddr)},
                    {destination_address, inet_parse:ntoa(Daddr)}]}|Acc]);
header([#tcp{sport = Sport, dport = Dport, ackno = Ackno, seqno = Seqno,
            win = Win, cwr = CWR, ece = ECE, urg = URG, ack = ACK, psh = PSH,
            rst = RST, syn = SYN, fin = FIN}|Rest], Acc) ->
    Flags = [ F || {F,V} <- [{cwr, CWR}, {ece, ECE}, {urg, URG}, {ack, ACK},
                   {psh, PSH}, {rst, RST}, {syn, SYN}, {fin, FIN} ], V =:= 1 ],
    header(Rest, [{tcp, [{source_port, Sport}, {destination_port, Dport},
                    {flags, Flags}, {seq, Seqno}, {ack, Ackno}, {win, Win}]}|Acc]);
header([#udp{sport = Sport, dport = Dport, ulen = Ulen}|Rest], Acc) ->
    header(Rest, [{udp, [{source_port, Sport}, {destination_port, Dport},
                    {ulen, Ulen}]}|Acc]);
header([#icmp{type = Type, code = Code}|Rest], Acc) ->
    header(Rest, [{icmp, [{type, Type}, {code, Code}]}|Acc]);
header([#icmp6{type = Type, code = Code}|Rest], Acc) ->
    header(Rest, [{icmp6, [{type, Type}, {code, Code}]}|Acc]);
header([Hdr|Rest], Acc) when is_tuple(Hdr) ->
    header(Rest, [{header, Hdr}|Acc]);
header([Payload|Rest], Acc) when is_binary(Payload) ->
    header(Rest, [{payload, to_ascii(Payload)},
            {payload_size, byte_size(Payload)}|Acc]).

packet(Format, Bin) ->
    packet(Format, Bin, []).
packet([], _Bin, Acc) ->
    lists:reverse(Acc);
packet([binary|Rest], Bin, Acc) ->
    packet(Rest, Bin, [{packet, Bin}|Acc]);
packet([hex|Rest], Bin, Acc) ->
    packet(Rest, Bin, [{packet, to_hex(Bin)}|Acc]).

to_ascii(Bin) when is_binary(Bin) ->
    [ to_ascii(C) || <<C:8>> <= Bin ];
to_ascii(C) when ?is_print(C) -> C;
to_ascii(_) -> $..

to_hex(Bin) when is_binary(Bin) ->
    [ integer_to_list(N, 16) || <<N:8>> <= Bin ].

ether_addr(MAC) ->
    string:join(to_hex(MAC), ":").

timestamp(Now) when is_tuple(Now) ->
    iso_8601_fmt(calendar:now_to_local_time(Now)).

iso_8601_fmt(DateTime) ->
    {{Year,Month,Day},{Hour,Min,Sec}} = DateTime,
    lists:flatten(io_lib:format("~4.10.0B-~2.10.0B-~2.10.0B ~2.10.0B:~2.10.0B:~2.10.0B",
            [Year, Month, Day, Hour, Min, Sec])).
