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
    error_logger:info_report("gen_server:start_link(~p)~n",[[{local, Name},?MODULE,[],[],self()]]),
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
    State = #state{instance=Instance, option_element_sorted = OptionElementSorted},
    case lists:keyfind(matchfun, 1, OptionElementSorted) of
	{matchfun, MatchFun} -> 
	    NewState1 = State#state{matchfun = MatchFun}, 
	    case lists:keyfind(message, 1, OptionElementSorted) of
		{message, Message} -> 
		    NewState2 = NewState1#state{message=Message}, 
		    Res = {ok, NewState2};
		false -> 
		    io:format("Message not given!!~n",[]),
		    Res = {stop, message_not_given}
	    end;

	false -> 
	    io:format("MatchFun not found!!~n",[]),
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
	_     ->
	    error_logger:info_msg("Logging: Instance: ~p, PID: ~p",[State#state.instance, self()]),
	    error_logger:info_msg("Message: ~p~n",[State#state.message]),
	    error_logger:info_report([
				      self(),	   
						% Source
				      {source_address, Saddr},
				      {source_port, Sport},

						% Destination
				      {destination_address, Daddr},
				      {destination_port,Dport},

				      {protocol, Proto},
				      {payload_bytes, byte_size(Payload)},
				      {payload, epcap_port_lib:to_ascii(Payload)}
				     ])
    end,
    Reply = ok,
    {reply, Reply, State};
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
	_     ->
	    error_logger:info_msg("Logging: Instance: ~p, PID: ~p, at ~p~n",[State#state.instance, self(),epcap_port_lib:timestamp(Time)]),
	    error_logger:info_msg("Message: ~p~n",[State#state.message]),
	    error_logger:info_report([
				      self(),	   
				      {time, epcap_port_lib:timestamp(Time)},
				      {caplen, byte_size(Packet)},
				      {len, Len},
				      {datalink, pkt:link_type(DLT)},

						% Source
				      {source_macaddr, string:join(epcap_port_lib:ether_addr(Ether#ether.shost), ":")},
				      {source_address, inet_parse:ntoa(Saddr)},
				      {source_port, epcap_port_lib:port(sport, Hdr)},

						% Destination
				      {destination_macaddr, string:join(epcap_port_lib:ether_addr(Ether#ether.dhost), ":")},
				      {destination_address, inet_parse:ntoa(Daddr)},
				      {destination_port, epcap_port_lib:port(dport, Hdr)},

				      {protocol, pkt:proto(Proto)},
				      {protocol_header, epcap_port_lib:header(Hdr)},

				      {payload_bytes, byte_size(Payload)},
				      {payload, epcap_port_lib:payload(Payload)}
				     ])
    end,
    {noreply, State};
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
terminate(_Reason, _State) ->
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
