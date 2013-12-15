-module(s10).

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
    Res_content_start = application:start(stream),
    io:format("content_app started Res: ~p~n",[Res_content_start]),
    %% traces for testing
    %%dbg:tracer(),
    %%dbg:p(all,c),
    %%dbg:tpl(epcap_server, x),
    %%dbg:tpl(content_server, x),
    %%dbg:tpl(epcap_root_sup, x),
    %%dbg:tpl(content_root_sup, x),	
    %%dbg:tpl(echo_server, x),
    %%dbg:tpl(stream_worker, x),
    %%dbg:tpl(supervisor, x),
    %%dbg:p(new, m),
    %%dbg:p(new, p),
    T = aho_corasick:tree(["meldung","thema"]),
    MatchFun1 = fun(Payload) ->                    
                        R = aho_corasick:match_tree(T, Payload), 
                        case R of
				[] -> fail; % not found
				Other -> Other % found
			end
                end,
    {ok, Result1} = rule:start([{epcap_port,[{interface, "eth0"}, {filter, "tcp"}]}, {stream, []}, {content, [{matchfun, MatchFun1}, {message, "Found: *meldung* oder *thema*"}]}]),
    io:format("Start result 1: ~p~n",[Result1]).

