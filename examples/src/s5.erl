-module(s5).

%% API
-export([s/0]).
s()->
    %% test case:
    %% start 2 rules

    application:start(sasl),
    Res_epcap_port_start = application:start(epcap_port),
    io:format("epcap_port_app started Res: ~p~n",[Res_epcap_port_start]),	
    Res_content_start = application:start(content),
    io:format("content_app started Res: ~p~n",[Res_content_start]),	
    Res_content_start = application:start(defrag),
    io:format("content_app started Res: ~p~n",[Res_content_start]),
    %% traces for testing
    dbg:tracer(),
    dbg:p(all,c),
    %%dbg:tpl(epcap_server, x),
    %%dbg:tpl(content_server, x),
    %%dbg:tpl(epcap_root_sup, x),
    %%dbg:tpl(content_root_sup, x),	
    %%dbg:tpl(defrag_server, x),
    dbg:tpl(defrag_worker, x),
    %%dbg:tpl(supervisor, x),
    dbg:p(new, m),
    dbg:p(new, p),
    MatchFun1 = fun(Payload) -> 
			A = parser_combinator_bitstring:pBinarystring(<<"GET">>),
			B = parser_combinator_bitstring:pUntilN( A, 100 ),
			C = parser_combinator_bitstring:pBinarystringCaseInsensitive(<<"MELDUNG">>),
			E = parser_combinator_bitstring:pBetweenN(B, C,14),
			parser_combinator_bitstring:parse(E,Payload) end,

    {ok, Result1} = rule:start([{epcap_port,[{interface, "eth0"}]}, {stream, []}, {content, [{matchfun, MatchFun1}, {message, "Found: GET*Meldung*"}]}]),
    io:format("Start result 1: ~p~n",[Result1]),
    MatchFun2 = fun(Payload) -> 
			A = parser_combinator_bitstring:pBinarystring(<<"GET">>),
			B = parser_combinator_bitstring:pUntilN( A, 100 ),
			C = parser_combinator_bitstring:pBinarystringCaseInsensitive(<<"thema">>),
			E = parser_combinator_bitstring:pBetweenN(B, C,14),
			parser_combinator_bitstring:parse(E,Payload) end.
    %%{ok, Result2} = rule:start([{epcap_port,[{interface, "tcp"}]}, {stream, []}, {content, [{matchfun, MatchFun2},{message, "Found: GET*Thema*"}]}]),
    %%io:format("Start result 2: ~p~n",[Result2]).

