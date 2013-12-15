-module(s12_PF_RING_cluster).

%% API
-export([s/1]).

s([Cluster_ID])->
    s(Cluster_ID);
s(Cluster_ID)when not(is_integer(Cluster_ID))->
    s(string:to_integer(Cluster_ID));
s(Cluster_ID)when is_integer(Cluster_ID)->
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
    Pattern = binary:compile_pattern([<<"meldung">>, <<"thema">>, <<"Ubuntu">>, <<16#0b, 16#07, 16#69, 16#72, 16#8b, 16#00, 16#d0, 16#28, 16#a9, 16#4b>>]),
    MatchFun1 = fun(Payload) ->  
			R = binary:matches(Payload, Pattern, []),                  
                        case R of
				[] -> fail; % not found
				Other -> Other % found
			end
                end,
    {ok, Result1} = rule:start([{epcap_port,[{interface, "eth0"}, {cluster_id, Cluster_ID}, {filter, "tcp"}]}, {defrag, []}, {content, [{matchfun, MatchFun1}, {message, "Found: *meldung* oder *thema* oder * Ubunt* oder <<16#0b, 16#07, 16#69, 16#72, 16#8b, 16#00, 16#d0, 16#28, 16#a9, 16#4b>>"}]}]),
    io:format("Start result 1: ~p~n",[Result1]).

