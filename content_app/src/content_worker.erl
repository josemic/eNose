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
-module(content_worker).

-behaviour(gen_server).

-include_lib("pkt/include/pkt.hrl").
%% API
-export([start_link/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, stop/1, code_change/3]).

-define(SERVER, ?MODULE). 

-record(state, {
	  received_packets::integer(),
	  received_bytes::integer(),
	  epcap_worker_pid::pid(),
	  instance::integer(),
	  matchfun::function(), 
	  option_element_sorted::[tuple()],
          message::string()
	 }).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------


start_link(Instance, OptionList)-> %% when is_integer(Instance) and is_list(InterfaceOptions) ->
    Instance_s = integer_to_list(Instance),
    Ref_s = erlang:ref_to_list(make_ref()),
    Fun = fun(ElementX,ElementY) -> (element(1,ElementX) > element(1,ElementY)) end,
    %% sort interface options alphabetically after insertion.
    OptionListSorted = lists:sort(Fun, OptionList),
    %% make sure the name is unique
						%Name_s = ?MODULE_STRING ++ "_" ++ Instance_s ++ "_" ++ Ref_s ++ lists:flatten(io_lib:format("~p", [OptionListSorted])),
    Name_s = ?MODULE_STRING ++ "_" ++ Instance_s ++ "_" ++ Ref_s ++ "_" ++ lists:flatten(io_lib:format("~p",[now()])) ++ "_" ++ lists:flatten(io_lib:format("~p", [OptionListSorted])),
    Name = list_to_atom (Name_s),
    lager:notice("gen_server:start_link(~p)~n",[[{local, Name},?MODULE,[],[],self()]]),
    gen_server:start_link({local,Name},?MODULE,[Instance, OptionList],[]).
%%gen_server:start_link(?MODULE,[Instance, OptionList],[]).


stop(WorkerPid) ->
    gen_server:call(WorkerPid, stop).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init([Instance, OptionElementSorted]) ->    
    State = #state{received_packets = 0, received_bytes = 0, instance=Instance, option_element_sorted = OptionElementSorted},
    case lists:keyfind(matchfun, 1, OptionElementSorted) of
	{matchfun, MatchFun} -> 
	    NewState1 = State#state{matchfun = MatchFun}, 
	    case lists:keyfind(message, 1, OptionElementSorted) of
		{message, Message} -> 
		    NewState2 = NewState1#state{message=Message}, 
		    Res = {ok, NewState2};
		false -> 
		    lager:error("Message not given!!~n",[]),
		    Res = {stop, message_not_given}
	    end;

	false -> 
	    lager:error("MatchFun not found!!~n",[]),
	    State =  #state{instance=Instance, matchfun = undefined, 
			    option_element_sorted = OptionElementSorted},
	    Res = {stop, matchfun_not_found}
    end, 
    Res.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call({payload_section, Saddr, Sport, Daddr, Dport, Payload}, _From, State) ->
    Proto = tcp,
    Matchfun = State#state.matchfun,
    case (Matchfun(Payload)) of
	fail ->
	    ok;
	{found, StartLengthList}     ->
            ok = print_result(StartLengthList, Payload, Saddr,Sport, Daddr, Dport, Proto, State)

    end,
    StateNew = State#state{received_packets= State#state.received_packets+1, received_bytes= State#state.received_bytes + byte_size(Payload)},
    Reply = ok,
    {reply, Reply, StateNew};
handle_call(stop, _From, State) ->
    {stop, normal, ok, State};
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.
%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------


handle_info({packet, DLT, Time, Len, Packet}, State) ->
    [Ether, IP, Hdr, Payload] = epcap_port_lib:decode(pkt:link_type(DLT), Packet),
    {Saddr, Daddr, Proto} = case IP of
				#ipv4{saddr = S, daddr = D, p = P} ->
				    {S,D,P};

				#ipv6{saddr = S, daddr = D, next = P} ->
				    {S,D,P}
			    end,
    Matchfun = State#state.matchfun,
    case (Matchfun(Payload)) of
	fail ->
	    ok;
        Found ->
	    lager:notice("Logging: Instance: ~p, PID: ~p, at ~p~n",[State#state.instance, self(),epcap_port_lib:timestamp(Time)]),
	    lager:notice("Message: ~p, ~n~nPattern found: ~p~n",[State#state.message, Found]),
	    lager:notice("Received packages: ~p, Received bytes: ~p~n",[State#state.received_packets, State#state.received_bytes]),
	    lager:notice("Self: ~p~n",[self()]), 
            lager:notice("time: ~p~n",[epcap_port_lib:timestamp(Time)]),
	    lager:notice("caplen: ~p~n",[byte_size(Packet)]), 
	    lager:notice("len: ~p~n",[Len]),
	    lager:notice("datalink: ~p~n",[pkt:link_type(DLT)]),
            lager:notice("source_address: ~p~n", [inet_parse:ntoa(Saddr)]), 
	    lager:notice("source_port: ~p~n",[string:join(epcap_port_lib:ether_addr(Ether#ether.shost), ":")]),
            lager:notice("destination_address: ~p~n",[inet_parse:ntoa(Daddr)]), 
            lager:notice("destination_port: ~p~n",[epcap_port_lib:port(sport, Hdr)]), 
	    lager:notice("protocol: ~p~n",[pkt:proto(Proto)]), 
	    lager:notice("protocol_header: ~p~n",[epcap_port_lib:header(Hdr)]),
	    lager:notice("payload_bytes: ~p~n", [byte_size(Payload)]), 
            lager:notice("payload: ~p~n", [epcap_port_lib:to_ascii(Payload)])
    end,
    StateNew = State#state{received_packets = State#state.received_packets+1, received_bytes= State#state.received_bytes + byte_size(Payload)},
    {noreply, StateNew};
handle_info(_Info, State) -> 
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, State) ->
    lager:notice("Received packages: ~p, Received bytes: ~p~n",[State#state.received_packets, State#state.received_bytes]),
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
print_result([], _Payload, _Saddr, _Sport, _Daddr, _Dport, _Proto, _State) ->
            ok;

print_result([{Start, Length}|StartLengthListTail], Payload, Saddr,Sport, Daddr, Dport, Proto, State) ->
            <<_Ignore:Start/binary, Found/binary>> = <<Payload/binary>>,
	    <<Result:Length/binary, _Rest/binary>> = <<Found/binary>>, 
	    lager:notice("Logging: Instance: ~p, PID: ~p",[State#state.instance, self()]),
	    lager:notice("Message: ~p, ~n~nPattern found: ~p~n",[State#state.message, epcap_port_lib:to_ascii(Result)]),
	    lager:notice("Received packages: ~p, Received bytes: ~p~n",[State#state.received_packets, State#state.received_bytes]),
	    lager:notice("Self: ~p~n", [self()]),
            lager:notice("source_address: ~p~n", [Saddr]),
	    lager:notice("source_port: ~p~n", [Sport]), 
	    lager:notice("destination_address: ~p~n", [Daddr]), 
	    lager:notice("destination_port: ~p~n", [Dport]), 
	    lager:notice("protocol: ~p~n", [Proto]),
	    lager:notice("Pattern starting: ~p~n", [State#state.received_bytes+Start]), 
	    lager:notice("Pattern ending: ~p~n", [State#state.received_bytes+Length]),
            lager:notice("Found pattern: ~p~n", [epcap_port_lib:to_ascii(Result)]),
            print_result(StartLengthListTail, Payload, Saddr,Sport, Daddr, Dport, Proto, State).
