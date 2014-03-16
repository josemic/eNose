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
-module(stream_server).

-behaviour(gen_server).
-include_lib("pkt/include/pkt.hrl").
-include("../../common/include/debug_macro.hrl").
-include("../../common/include/decoded.hrl").

%% API
-export([start_link/0, start_worker/2, stop_worker/1, remove_connection_worker_by_pid/1, rule_element_register/3, 
	 rule_element_unregister/3]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

-define(SERVER, ?MODULE). 

%%-define(DEBUG_SERVER, true).

-ifdef(DEBUG_SERVER).
%%-define(GEN_FSM_OPTS, {debug, [trace, {log_to_file, "log/stream/trace_server.log"}]}).
-define(GEN_FSM_OPTS, {debug, [{log_to_file, "log/stream/trace_server.log"}]}).
%%-define(GEN_FSM_OPTS, {debug, [{install,{Dbg_fun,state}}]}).
%%-define(GEN_FSM_OPTS, {debug, [{install,{Dbg_fun,state}}, {log_to_file, "log/stream/trace_server.log"}]}).
%%-define(GEN_FSM_OPTS, {debug, [trace]}).
-else.
-define(GEN_FSM_OPTS, []).
-endif.

-record(state, {
          crash::boolean(),
	  child_worker_instance::integer(),
	  child_worker_pid_list::[tuple()],
          connection_worker_instance::integer(),
	  connection_worker_pid_list::[tuple()]}). % consists of tuple {AddressTuple, ConnectionWorkerPid}

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
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

start_worker(AddressTuple, PacketTuple) ->
    gen_server:call(?MODULE, {start_worker, AddressTuple, PacketTuple}, infinity).

stop_worker(WorkerPid) ->
    gen_server:call(?MODULE, {stop_worker, WorkerPid}, infinity).

rule_element_register(_RuleOptionList, ChildWorkerPid, _RuleElements)->
    register_child_worker_Pid(ChildWorkerPid),
    {ok, whereis(?MODULE)}. 

rule_element_unregister(_WorkerPid, ChildWorkerPid, _RuleOptionList)->
    unregister_child_worker_Pid(ChildWorkerPid),
    ok.

register_child_worker_Pid(ChildWorkerPid) ->
    gen_server:call(?MODULE, {register_child_worker_Pid,  ChildWorkerPid}, infinity).

unregister_child_worker_Pid(ChildWorkerPid) ->
    gen_server:call(?MODULE, {unregister_child_worker_Pid,  ChildWorkerPid}, infinity).

%%register_connection_worker_Pid(ConnectionWorkerPid) ->
%%    gen_server:call(?MODULE, {register_connection_worker_Pid,  ConnectionWorkerPid}).
%%
%%unregister_connection_worker_Pid(ConnectionWorkerPid) ->
%%    gen_server:call(?MODULE, {unregister_connection_worker_Pid,  ConnectionWorkerPid}).

remove_connection_worker_by_pid(Pid) ->
    gen_server:call(?MODULE, {remove_connection_worker_by_pid,  Pid}, infinity).

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
init([]) ->
    io:format("Stream_server started\n"),
    {ok, #state{connection_worker_instance = 0, child_worker_instance = 0, connection_worker_pid_list = [], child_worker_pid_list = [], crash = false}}.


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

handle_call({start_worker, AddressTuple, PacketTuple}, _From, State) ->
    StateNew = State#state{connection_worker_instance = (State#state.connection_worker_instance + 1)}, 	
    Reply = stream_root_sup:start_worker(StateNew#state.connection_worker_instance, AddressTuple, PacketTuple),
    {reply, Reply, StateNew};
handle_call({stop_worker, Pid}, _From, State) ->
    Connection_worker_pid_list = State#state.connection_worker_pid_list,
    case remove_connection_worker_by_pid(Connection_worker_pid_list, Pid) of
	{not_found, Pid} ->		
	    StateNew = State;
    	{found, Pid, Connection_worker_pid_list} ->
	    StateNew = State#state{connection_worker_pid_list = Connection_worker_pid_list}
    end,
    StateNew2 = State#state{connection_worker_instance = StateNew#state.connection_worker_instance - 1},
    Reply = stream_root_sup:stop_worker(Pid),
    {reply, Reply, StateNew2};
handle_call({register_child_worker_Pid, ChildWorkerPid}, _From, State) ->
    NewState = State#state{child_worker_instance = State#state.child_worker_instance+1, child_worker_pid_list = [ChildWorkerPid|State#state.child_worker_pid_list]},
    {reply, ok, NewState};
handle_call({unregister_child_worker_Pid,  ChildWorkerPid}, _From, State) ->
    ChildWorkerPid_list = lists:delete(ChildWorkerPid, State#state.child_worker_pid_list),
    NewState = State#state{child_worker_pid_list = ChildWorkerPid_list},
    Response = case ChildWorkerPid_list of 
		   [] ->
		       no_children_left; % child can be stopped
		   _NonEmptyLits ->
		       children_left     % still children left, child can not be stopped
	       end,     
    {reply, Response, NewState};

handle_call({remove_connection_worker_by_pid, Pid}, _From, State) ->
    Connection_worker_pid_list = State#state.connection_worker_pid_list,
    case remove_connection_worker_by_pid(Connection_worker_pid_list, Pid) of
	{not_found, Pid} ->		
	    StateNew = State;
    	{found, Pid, Connection_worker_pid_list_new} ->
	    StateNew = State#state{connection_worker_pid_list = Connection_worker_pid_list_new}
    end,
    {reply, ok, StateNew}.


%%handle_call({register_connection_worker_Pid, ConnectionWorkerPid}, _From, State) ->
%%    NewState = State#state{instance = State#state.instance+1, connection_worker_pid_list = [ConnectionWorkerPid|State#state.connection_worker_pid_list]},
%%    {reply, ok, NewState};
%%handle_call({unregister_connection_worker_Pid,  ConnectionWorkerPid}, _From, State) ->
%%    ConnectionWorker_pid_list = lists:delete(ConnectionWorkerPid, State#state.connection_worker_pid_list),
%%    NewState = State#state{connection_worker_pid_list = ConnectionWorker_pid_list},
%%    Response = case ConnectionWorker_pid_list of 
%%		   [] ->
%%		       no_children_left; % child can be stopped
%%		   _NonEmptyLits ->
%%		       children_left     % still children left, child can not be stopped
%%	       end,     
%%    {reply, Response, NewState}.

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
handle_info({packet, DLT, _Time, _Len, Data}, State) ->
    Result = epcap_port_lib:decode(DLT, Data, State#state.crash),
    case Result of 
	{ok, Packet} -> 
            StateNew = handle_received_packet(Packet, DLT, _Time, _Len, Data, State);
	{failed, SoFarDecoded, DecodingFailed} ->
	    %% drop packet and issue warning
	    lager:warning("Invalid packet received: Decoded: ~p Decoding Failed: ~p~n", [pretty_print_list(SoFarDecoded), lager:pr(DecodingFailed, ?MODULE)]),
	    StateNew = State
    end,
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

remove_connection_worker_by_pid(Connection_worker_list, Pid)->
    remove_connection_worker_by_pid(Connection_worker_list, [], Pid, not_found).

remove_connection_worker_by_pid([], _Accum, Pid, not_found)->
    {not_found, Pid};		
remove_connection_worker_by_pid([], Accum, Pid, found)->
    {found, Pid, lists:reverse(Accum)};
remove_connection_worker_by_pid([{_AddressTuple, SearchPid}|AddressTupleElements], Accum, SearchPid, _Found)->
    remove_connection_worker_by_pid(AddressTupleElements, Accum, SearchPid, found);		
remove_connection_worker_by_pid([AddressTupleElement|AddressTupleElements], Accum, SearchPid, Found)->
    remove_connection_worker_by_pid(AddressTupleElements, [AddressTupleElement| Accum],SearchPid, Found).

%% Insert connection worker with connection identification {Source_address, Source_port}, {Destination_address, Destination_port} 
%% into connection worker list
%%
insert_element(Connection_worker_list, {AddressTuple, Pid})->
    [{AddressTuple, Pid}|Connection_worker_list]. 

%% Each connection is uniquely identfied by an address tuple
%% When searching for the address tuple, then it is searched / matched against:
%% {{Destination_address, Destination_port},{Source_address, Source_port}}
%% and
%% {{Source_address, Source_port}, {Destination_address, Destination_port}}

get_connection_worker_pid_by_address_tuple([], AddressTuple)->
    {not_found, AddressTuple};
get_connection_worker_pid_by_address_tuple(
  [{{{Source_address, Source_port}, {Destination_address, Destination_port}}, Pid}|_AddressTupleElements], 
  {{Source_address, Source_port}, {Destination_address, Destination_port}}
 )->
    {found, initiator, Pid, {{Source_address, Source_port}, {Destination_address, Destination_port}}};
get_connection_worker_pid_by_address_tuple(
  [{{{Destination_address, Destination_port},{Source_address, Source_port}}, Pid}|_AddressTupleElements], 
  {{Source_address, Source_port}, {Destination_address, Destination_port}})->
    {found, responder, Pid, {{Destination_address, Destination_port},{Source_address, Source_port}}};
get_connection_worker_pid_by_address_tuple(
  [_AddressTupleElement|AddressTupleElements], 
  AddressTuple
 )->
    get_connection_worker_pid_by_address_tuple(AddressTupleElements, AddressTuple).

payloadsize(#ipv4{len = Len, hl = HL}, #tcp{off = Off}) ->
    Len - (HL * 4) - (Off * 4);

%% jumbo packet
payloadsize(#ipv6{len = 0, next = _Next}, #tcp{off = _Off}) ->
    %% XXX handle jumbo packet here
    io:format("Warning!!! Jumbo packet!!!"),
    0;
payloadsize(#ipv6{len = Len, next = ?IPPROTO_TCP}, #tcp{off = Off}) ->
    Len - (Off * 4);


%% additional extension headeres
payloadsize(#ipv6{len = _Len, next = _Next}, #tcp{off = _Off}) ->
    %% XXX handle extension headers here
    io:format("Warning!!! Extension packet!!!"),
    0.

handle_received_packet(Packet, DLT, _Time, _Len, Data, State) -> 
    [_EtherIgnore, IP, TCP, PayloadPadded] = Packet,
    {Source_address, Destination_address, _Proto} = case IP of
							#ipv4{saddr = S, daddr = D, p = P} ->
							    {S,D,P};

							#ipv6{saddr = S, daddr = D, next = P} ->
							    {S,D,P}
						    end,
    IgnorePacketStatus = case IP of
			     #ipv4{} ->
				 Res1 = check_invalid_ip4_address(S,D),
				 Result1 = case Res1 of
					       equal -> 
						   lager:warning("Source address matches Destination address !, Decoded: ~p~nIgnoring packet~n", [pretty_print_list(Packet)]),
						   false;
					       source_ip4_address_invalid_end_0 ->
						   lager:warning("Source address ends on 0 !, Decoded: ~p~nIgnoring packet~n", [pretty_print_list(Packet)]),
						   false;
					       source_ip4_address_invalid_end_255 -> 
						   lager:warning("Source address ends on 255 , Decoded: ~p~nIgnoring packet~n", [pretty_print_list(Packet)]),
						   false;
					       destination_address_invalid_end_0 -> 
						   lager:warning("Destination address ends on 0 !, Decoded: ~p~nIgnoring packet~n", [pretty_print_list(Packet)]),
						   false;
					       destination_address_invalid_end_255 -> 
						   lager:warning("Destination address ends on 255 !, Decoded: ~p~nIgnoring packet~n", [pretty_print_list(Packet)]),
						   false;
					       source_address_invalid_start_10 -> 
						   lager:warning("Source address starts with 10 !, Decoded: ~p~nIgnoring packet~n", [pretty_print_list(Packet)]),
						   false;
					       destination_address_invalid_start_10 -> 
						   lager:warning("Destination address starts with 10 !, Decoded: ~p~nIgnoring packet~n", [pretty_print_list(Packet)]),
						   false;
					       source_address_invalid_start_172_xx -> 
						   lager:warning("Source address‎ is in range 192.16.x.x - 192.31.x.x !, Decoded: ~p~nIgnoring packet~n", [pretty_print_list(Packet)]),
						   false;
					       destination_address_invalid_start_172_xx -> 
						   lager:warning("Destination address is in range 192.16.x.x - 192.31.x.x !, Decoded: ~p~nIgnoring packet~n", [pretty_print_list(Packet)]),
						   false;
					       source_address_invalid_start_192_168 -> 
						   lager:warning("Source address starts with 192.168 !, Decoded: ~w~nIgnoring packet~n", [pretty_print_list(Packet)]),
						   false;
					       destination_address_invalid_start_192_168 -> 
						   lager:warning("Destination address starts with 192.168 !, Decoded: ~w~nIgnoring packet~n", [pretty_print_list(Packet)]),
						   false;
					       source_address_invalid_start_169_254 -> 
						   lager:warning("Source address starts with 169.254 !, Decoded: ~p~nIgnoring packet~n", [pretty_print_list(Packet)]),
						   false;
					       destination_address_invalid_start_169_254 -> 
						   lager:warning("Destination address starts with 169.254 !, Decoded: ~p~nIgnoring packet~n", [pretty_print_list(Packet)]),
						   false;
					       different ->
						   true
					   end,  
				 Res2 = check_connection_state_independent_invalid_flags(
					  TCP#tcp.cwr, 
					  TCP#tcp.ece,
					  TCP#tcp.urg,
					  TCP#tcp.ack,
					  TCP#tcp.psh,
					  TCP#tcp.rst,
					  TCP#tcp.syn,
					  TCP#tcp.fin),
				 Result2 = case Res2 of
					       null -> 
						   lager:warning("Invalid packet received: Flags CWR = ECE = URG = ACK = PSH = RST = SYN = FIN = 0 !~n, Decoded: ~p~nIgnoring packet~n", [pretty_print_list(Packet)]),
						   false;

					       syn_fin ->
						   lager:warning("Invalid packet received: Flags SYN = FIN = 1 !~n, Decoded: ~p~nIgnoring packet~n", [pretty_print_list(Packet)]),
						   false;
					       fin_only ->
						   lager:warning("Invalid packet received: Flags CWR = ECE = URG = ACK = PSH = RST = SYN = 0, FIN = 1 !~n, Decoded: ~p~nIgnoring packet~n", [pretty_print_list(Packet)]),
						   false;
					       ok ->
						   true
					   end,
				 Result1 or Result2;

			     #ipv6{} ->
				 %% TODO
				 Result1 = true, %% do not drop for now
                                 Result2 = true, %% do not drop for now
				 Result1 or Result2
			 end,
    {Result3, Opt} = try (pkt_tcp:options(TCP#tcp.opt)) of
			 Val -> 
			     {true, Val}
		     catch
			 _:_ -> 
			     lager:warning("Invalid TCP options field received !~n, Decoded: ~p~nIgnoring packet~n", [pretty_print_list(Packet)]),
			     {fail, undefined}
		     end,
    Res4 = check_tcp_port_for_non_zero(
	     TCP#tcp.sport, 
	     TCP#tcp.dport),
    Result4 = case Res4 of
		  sport_is_zero -> 
		      lager:warning("Invalid packet received: Source port = 0 !~n, Decoded: ~p~nIgnoring packet~n", [pretty_print_list(Packet)]),
		      false;
		  dport_is_zero -> 
		      lager:warning("Invalid packet received: Destination port = 0 !~n, Decoded: ~p~nIgnoring packet~n", [pretty_print_list(Packet)]),
		      false;
		  ok ->
		      true
	      end,
    Result = Result1 and Result2 and Result3 and Result4,
    case Result of 
	true ->
	    case  (TCP#tcp.syn == 1) of 
		true ->
		    ?DEBUG("Syn:{Ack:~p, Syn:~p, Fin:~p, _Rst:~p, SEG_SEQ:~p, SEG_ACK:~p, SEG_WND:~p, OPT:~p},~n
        {{Sender_address:~p, Sender_port:~p},~n
	 {Receiver_address:~p, Receiver_port:~p}},~n
			   _DLT:~p, _Time:~p, _Len:~p}~n", [TCP#tcp.ack, TCP#tcp.syn, TCP#tcp.fin, TCP#tcp.rst, TCP#tcp.seqno, TCP#tcp.ackno, TCP#tcp.win, TCP#tcp.opt, Source_address, TCP#tcp.sport, 
        Destination_address, TCP#tcp.dport, DLT, _Time, _Len]);
      false ->
       ok
    end,
    case get_connection_worker_pid_by_address_tuple(State#state.connection_worker_pid_list, 
						    AddressTuple = {{Source_address, TCP#tcp.sport},{Destination_address, TCP#tcp.dport}}) of
	{not_found, _AddressTuple} ->
            PayloadSize = payloadsize(IP, TCP),
	    <<Payload:PayloadSize/binary, Rest1/binary>> = <<PayloadPadded/binary>>,
	    Chksum_ok = case IP of
			    #ipv4{} ->
				IPSum = pkt:makesum(IP),
				TCPSum = pkt:makesum([IP, TCP, Payload]),
				case [IPSum, TCPSum] of 
				    [0,0] ->
					true;
				    [_,_] ->
					?DEBUG("Wrong checksum: {S:~p,D:~p,P:~p} {IPSum: ~p, TCPSum: ~p}~n Data:~p~n, DLT:~p~n, Decoded~w~n", [IP#ipv4.saddr,IP#ipv4.daddr,IP#ipv4.p, IPSum, TCPSum, Data, DLT, Packet]),
					false
				end;
			    #ipv6{} ->
				true % checksum not implemented for ipv6 
			end,
	    case Chksum_ok of
		true ->
		    case {TCP#tcp.ack, TCP#tcp.syn, TCP#tcp.fin, TCP#tcp.rst} of
			{0, 1, 0, 0} -> % Syn
                            Decoded = #decoded{payload = Payload,  payload_size = PayloadSize, opt_decoded = Opt, source_address = Source_address, destination_address = Destination_address},
			    StateNew1 = State#state{connection_worker_instance = State#state.connection_worker_instance + 1}, 	
			    {ok, ConnectionWorkerPid} = stream_root_sup:start_worker(
							  StateNew1#state.connection_worker_instance, 
							  {_Direction = initiator, IP, TCP, Decoded},
							  StateNew1#state.child_worker_pid_list),
			    StateNew2 = StateNew1#state{connection_worker_pid_list = 
							   insert_element(StateNew1#state.connection_worker_pid_list, {AddressTuple, ConnectionWorkerPid})};
			_Other -> 
			    %% drop packet, as it is out of band packet
                            ?DEBUG("Dropping packet as out of band:{Ack:~p, Syn:~p, Fin:~p, _Rst:~p, SEG_SEQ:~p, SEG_ACK:~p, SEG_WND:~p, OPT:~p},~n
                                     {{Sender_address:~p, Sender_port:~p},~n
                                      {Receiver_address:~p, Receiver_port:~p}},~n
                                      DLT:~p, Time:~p, Len:~p}~n", [TCP#tcp.ack, TCP#tcp.syn, TCP#tcp.fin, TCP#tcp.rst, TCP#tcp.seqno, TCP#tcp.ackno, TCP#tcp.win, Opt, Source_address, TCP#tcp.sport, 
                                      Destination_address, TCP#tcp.dport, DLT, _Time, _Len]),
			    StateNew2 = State
                    end;
		false ->
                    StateNew2 = State,
                    ?DEBUG("Dropping packet as checksum not ok: {Ack:~p, Syn:~p, Fin:~p, Rst:~p, SEG_SEQ:~p, SEG_ACK:~p, SEG_WND:~p, OPT:~p},~n
                                     {{Sender_address:~p, Sender_port:~p},~n
                                      {Receiver_address:~p, Receiver_port:~p}},~n
                                      _DLT:~p, _Time:~p, _Len:~p}~n", [TCP#tcp.ack, TCP#tcp.syn, TCP#tcp.fin, TCP#tcp.rst, TCP#tcp.seqno, TCP#tcp.ackno, TCP#tcp.win, Opt, Source_address, TCP#tcp.sport, Destination_address, TCP#tcp.dport, DLT, _Time, _Len]),
		    ok % ignore packet as checksum  not ok
	    end;

	{found, Direction, WorkerPid, _Any} ->
            Opt = pkt_tcp:options(TCP#tcp.opt),
	    PayloadSize = payloadsize(IP, TCP),
	    <<Payload:PayloadSize/binary, Rest2/binary>> = <<PayloadPadded/binary>>,
	    Chksum_ok = case IP of
			    #ipv4{} ->
				IPSum = pkt:makesum(IP),
				TCPSum = pkt:makesum([IP, TCP, Payload]),
				case [IPSum, TCPSum] of 
				    [0,0] ->
					true;
                                    [_,_] ->
					?DEBUG("Wrong checksum: {S:~p,D:~p,P:~p} {IPSum: ~p, TCPSum: ~p}~n Data:~p~n, DLT:~p~n, Decoded~w~n", [IP#ipv4.saddr,IP#ipv4.daddr,IP#ipv4.p, IPSum, TCPSum, Data, DLT, Packet]),
					false
				end;
			    #ipv6{} ->
				true % checksum not implemented for ipv6 
			end,
	    case Chksum_ok of
                true -> 
		    Decoded = #decoded{payload = Payload,  payload_size = PayloadSize, opt_decoded = Opt, source_address = Source_address, destination_address = Destination_address},
                    stream_worker:send_packet(WorkerPid, 
					      {Direction, IP, TCP, Decoded});
		false ->
		    ok % ignore packet as checksum is not ok			
	    end,
            StateNew2 = State
    end,
    StateNew2;
false ->
    %% ignore packet
    State
end.


check_invalid_ip4_address(S,D) when S==D ->
       address_equal;
%% not sure if this is still relevant:
%% Review RFC 6761
%%check_invalid_ip4_address({_SA1,_SA2,_SA3,_SA4=0},_D) ->
%%       source_ip4_address_invalid_end_0;
check_invalid_ip4_address({_SA1,_SA2,_SA3,_SA4=255},_D) ->
       source_ip4_address_invalid_end_255;
%% not sure if this is still relevant:
%% Review RFC 6761
%%check_invalid_ip4_address(_S,{_DA1,_DA2,_DA3,_DA4=0}) ->
%%       destination_address_invalid_end_0;
check_invalid_ip4_address(_S,{_DA1,_DA2,_DA3,_DA4=255}) ->
       destination_address_invalid_end_255;
check_invalid_ip4_address({_SA1=10,_SA2,_SA3,SA4},_D) ->
       source_address_invalid_start_10;
check_invalid_ip4_address(_S,{_DA1=10,_DA2,_DA3,_DA4}) ->
       destination_address_invalid_start_10;
check_invalid_ip4_address({_SA1=172,SA2,_SA3,SA4},_D) when (SA2 >= 16) and (SA2 =< 31) ->
       source_address_invalid_start_172_xx;
check_invalid_ip4_address(_S,{_DA1=172,DA2,_DA3,_DA4}) when (DA2 >= 16) and (DA2 =< 31)->
       destination_address_invalid_start_172_xx;
%% not sure if this is still relevant:
%% Review RFC 6761
%%check_invalid_ip4_address({_SA1=192,_SA2=168,_SA3,SA4},_D) ->
%%       source_address_invalid_start_192_168;
%%check_invalid_ip4_address(_S,{_DA1=192,_DA2=168,_DA3,_DA4}) ->
%%       destination_address_invalid_start_192_168;
check_invalid_ip4_address({_SA1=169,_SA2=254,_SA3,SA4},_D) ->
       source_address_invalid_start_169_254;
check_invalid_ip4_address(_S,{_DA1=169,_DA2=254,_DA3,_DA4}) ->
       destination_address_invalid_start_169_254;
check_invalid_ip4_address(S,D) ->
       different.

check_connection_state_independent_invalid_flags(_CWR = 0, _ECE = 0, _URG = 0, _ACK = 0, _PSH = 0, _RST =0, _SYN = 0, _FIN = 0) ->
        %% Null (all flags are false)
	null;
check_connection_state_independent_invalid_flags(_CWR, _ECE, _URG, _ACK, _PSH, _RST, _SYN = 1, _FIN = 1) ->
        %% Syn-Fin plus anything
	syn_fin;
%%check_connection_state_independent_invalid_flags(_CWR = 0, _ECE = 0, _URG = 0, _ACK = 0, _PSH = 0, _RST = 0, _SYN = 0, _FIN = 1) ->
%%      %% only Fin
%%	fin_only;
check_connection_state_independent_invalid_flags(_CWR, _ECE, _URG, _ACK, _PSH, _RST, _SYN, _FIN) ->
	ok.

check_tcp_port_for_non_zero(_SPort=0, _Dport) ->
	sport_is_zero;
check_tcp_port_for_non_zero(_SPort, _Dport=0) ->
	dport_is_zero;
check_tcp_port_for_non_zero(_SPort, _Dport) ->
        ok.

pretty_print_list(List) ->
        pretty_print_list(List, []).

pretty_print_list([H|T], Acc) ->
        pretty_print_list(T,[lager:pr(H,?MODULE)|Acc]);
pretty_print_list([], Acc) ->
        lists:reverse(Acc). 

