-module(s3).

%% API
-export([s/0]).
s()->
    application:start(sasl),
    Res = application:start(epcap_port),
    io:format("epcap_port_app started Res: ~p~n",[Res]),	
    Res1 = application:start(content),
    io:format("content_app started Res: ~p~n",[Res1]),	
    %%dbg:tracer(),
    %%dbg:p(all,c),
    %%dbg:tpl(epcap_port_server, x),
    %%dbg:tpl(content_server, x),
    %%dbg:tpl(epcap_root_sup, x),
    %%dbg:tpl(content_port_root_sup, x),	
    %%dbg:tpl(echo_server, x),
    %%dbg:tpl(supervisor, x),
    %%dbg:p(new, m),
    %%dbg:p(new, p),
    MatchFun1 = fun(Payload) -> 
			A = parser_combinator_bitstring:pBinarystring(<<"GET">>),
			B = parser_combinator_bitstring:pUntilN( A, 100 ),
			C = parser_combinator_bitstring:pBinarystringCaseInsensitive(<<"MELDUNG">>),
			E = parser_combinator_bitstring:pBetweenN(B, C,14),
			parser_combinator_bitstring:parse(E,Payload) end,

    Result1 = rule:start([{epcap_port,[{interface, "eth0"}]}, {content, [{matchfun, MatchFun1}, {message, "Found: GET*Meldung*"}]}]),
    io:format("Result: ~p~n",[Result1]).

