-module(s11_1).

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
    %%dbg:tracer(),
    %%dbg:p(all,c),
    %%dbg:tpl(epcap_server, x),
    %%dbg:tpl(content_server, x),
    %%dbg:tpl(epcap_root_sup, x),
    %%dbg:tpl(content_root_sup, x),	
    %%dbg:tpl(echo_server, x),
    %%dbg:tpl(defrag_worker, x),
    %%dbg:tpl(supervisor, x),
    %%dbg:p(new, m),
    %%dbg:p(new, p),
    {GotoDictNew, FailDict, OutputDictNew} = ahocorasick:trie([<<"meldung">>, <<"thema">>, <<"Ubuntu">>]),
    MatchFun1 = fun(Payload) ->  
			R = ahocorasick:find(GotoDictNew, FailDict, OutputDictNew, Payload),                  
                        case R of
				[] -> fail; % not found
				Other -> Other % found
			end
                end,
    {ok, Result1} = rule:start([{epcap_port,[{interface, "eth1"}, {filter, "tcp"}]}, {defrag, []}, {content, [{matchfun, MatchFun1}, {message, "Found: *meldung* oder *thema* oder * Ubunt*"}]}]),
    io:format("Start result 1: ~p~n",[Result1]).

