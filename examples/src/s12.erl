-module(s12).

%% API
-export([s/1]).

s([Interface]) when is_atom(Interface)->
   io:format("Interface:~p~n ", [Interface]), 
   s(atom_to_list(Interface));

s(Interface) when is_list(Interface)->
    application:start(sasl),
    %%error_logger:logfile({open, "logfile.txt"}), 
    error_logger:tty(false), 
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
    Pattern = binary:compile_pattern([<<"meldung">>, <<"thema">>, <<"Ubuntu">>, <<16#0b, 16#07, 16#69, 16#72, 16#8b, 16#00, 16#d0, 16#28, 16#a9, 16#4b>>]),
    MatchFun1 = fun(Payload) ->  
			R = binary:matches(Payload, Pattern, []),                  
                        case R of
				[] -> fail; % not found
				Other -> Other % found
			end
                end,
    {ok, Result1} = rule:start([{epcap_port,[{interface, Interface}, {filter, "tcp"}]}, {stream, []}, {content, [{matchfun, MatchFun1}, {message, "Found: *meldung* oder *thema* oder * Ubunt* oder <<16#0b, 16#07, 16#69, 16#72, 16#8b, 16#00, 16#d0, 16#28, 16#a9, 16#4b>>"}]}]),
    io:format("Start result 1: ~p~n",[Result1]).

