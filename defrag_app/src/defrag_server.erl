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
-module(defrag_server).

-behaviour(gen_server).
-include_lib("pkt/include/pkt.hrl").

%% API
-export([start_link/0, start_worker/2, stop_worker/1, remove_connection_worker_by_pid/1, rule_element_register/3, 
	 rule_element_unregister/3]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

-define(SERVER, ?MODULE). 

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
    gen_server:call(?MODULE, {start_worker, AddressTuple, PacketTuple}).

stop_worker(WorkerPid) ->
    gen_server:call(?MODULE, {stop_worker, WorkerPid}).

rule_element_register(_RuleOptionList, ChildWorkerPid, _RuleElements)->
    register_child_worker_Pid(ChildWorkerPid),
    {ok, whereis(?MODULE)}. 

rule_element_unregister(_WorkerPid, ChildWorkerPid, _RuleOptionList)->
    unregister_child_worker_Pid(ChildWorkerPid),
    ok.

register_child_worker_Pid(ChildWorkerPid) ->
    gen_server:call(?MODULE, {register_child_worker_Pid,  ChildWorkerPid}).

unregister_child_worker_Pid(ChildWorkerPid) ->
    gen_server:call(?MODULE, {unregister_child_worker_Pid,  ChildWorkerPid}).

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
    io:format("Defrag_server started\n"),
    {ok, #state{connection_worker_instance = 0, child_worker_instance = 0, connection_worker_pid_list = [], child_worker_pid_list = [], crash = true}}.


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
    Reply = defrag_root_sup:start_worker(StateNew#state.connection_worker_instance, AddressTuple, PacketTuple),
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
    Reply = defrag_root_sup:stop_worker(Pid),
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
	    StateNew = State#state{connection_worker_pid_list = Connection_worker_pid_list_new, 
                                   connection_worker_instance = State#state.connection_worker_instance-1}
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
handle_info({packet, DLT, Time, Len, Data}, State) ->
    Packet = epcap_port_lib:decode(DLT, Data, State#state.crash),
    [_EtherIgnore, IP, TCP, PayloadPadded] = Packet,
    {Saddr, Daddr, _Proto} = case IP of
				 #ipv4{saddr = S, daddr = D, p = P} ->
				     {S,D,P};

				 #ipv6{saddr = S, daddr = D, next = P} ->
				     {S,D,P}
			     end,
    Source_address = Saddr,
    %Source_address = inet_parse:ntoa(Saddr),
    %%Source_port = epcap_port_lib:port(sport, TCP),
    %Destination_address = inet_parse:ntoa(Daddr),
    Destination_address = Daddr,
    %%Destination_port = epcap_port_lib:port(dport, TCP),
    #tcp{sport = Sport, dport = Dport, ackno = Ackno, seqno = Seqno,
         win = Win, cwr = _CWR, ece = _ECE, urg = _URG, ack = ACK, psh = _PSH,
         rst = RST, syn = SYN, fin = FIN, opt = OptBinary} = TCP, 
    Ack = (ACK =:=1),
    Rst = (RST =:=1),
    Syn = (SYN =:=1),
    Fin = (FIN =:=1),
    Opt = pkt_tcp:options(OptBinary),
    case get_connection_worker_pid_by_address_tuple(State#state.connection_worker_pid_list, 
						    {{Source_address, Sport},{Destination_address, Dport}}) of
	{not_found, _AddressTuple} ->
	    %%Header = epcap_port_lib:header(TCP),
	    %%{flags, Flags} = lists:keyfind(flags, 1, Header),
	    %%Syn = lists:member(syn, Flags),
	    %%Ack = lists:member(ack, Flags),
	    %%Fin = lists:member(fin, Flags),
	    %%Rst = lists:member(rst, Flags),
            %%{seq, Seqno} = lists:keyfind(seq, 1, Header),
            %%{ack, Ackno} = lists:keyfind(ack, 1, Header),
            %%{win, Win} = lists:keyfind(win, 1, Header),
            %%{opt, OptBinary} = lists:keyfind(opt, 1, Header),
            %%Opt = tcp_options(OptBinary),
            PayloadSize = payloadsize(IP, TCP),
            Payload = <<PayloadPadded:PayloadSize/binary>>,
	    Chksum_ok = case IP of
			    #ipv4{} ->
				IPSum = pkt:makesum(IP),
				TCPSum = pkt:makesum([IP, TCP, Payload]),
				case [IPSum, TCPSum] of 
				    [0,0] ->
					true;
				    [_,_] ->
					io:format("Wrong checksum: {S:~p,D:~p,P:~p} {IPSum~p, TCPSum~p}~n Packet:~p~nDecoded~w~n", [IP#ipv4.saddr,IP#ipv4.daddr,IP#ipv4.p, IPSum, TCPSum, Packet, pkt:decapsulate({pkt:dlt(DLT), Packet})]),
					false
				end;
			    #ipv6{} ->
				true % checksum not implemented for ipv6 
			end,
 	    case Chksum_ok of
		true ->
		    case {Ack, Syn, Fin, Rst, Seqno, Ackno, Win, Opt} of
			{false, true, false, false, _, _, _, _} -> % Syn
			    StateNew1 = State#state{connection_worker_instance = State#state.connection_worker_instance + 1}, 	
			    {ok, ConnectionWorkerPid} = defrag_root_sup:start_worker(
							  StateNew1#state.connection_worker_instance, 
							  {packet_with_addressing, {Ack, Syn, Fin, Rst, Seqno, Ackno, Win, Opt}, 
							   {{Source_address, Sport}, {Destination_address, Dport}}, 
							   DLT, Time, Len, Packet, PayloadSize=0}, 
							  StateNew1#state.child_worker_pid_list), 
			    AddressTuple = {{Source_address, Sport}, {Destination_address, Dport}},
			    StateNew = StateNew1#state{connection_worker_pid_list = 
							   insert_element(StateNew1#state.connection_worker_pid_list, {AddressTuple, ConnectionWorkerPid})};
			_Other -> 
			    %% drop packet, as it is out of band packet
			    StateNew = State
                    end;
		false ->
                    StateNew = State,
		    ok % ignore packet as checksum  not ok
	    end;

	{found, WorkerPid, _Any} ->
	    %%Header = epcap_port_lib:header(TCP),
	    %%{flags, Flags} = lists:keyfind(flags, 1, Header),
	    %%Syn = lists:member(syn, Flags),
	    %%Ack = lists:member(ack, Flags),
	    %%Fin = lists:member(fin, Flags),
	    %%Rst = lists:member(rst, Flags),
            %%{seq, Seqno} = lists:keyfind(seq, 1, Header),
            %%{ack, Ackno} = lists:keyfind(ack, 1, Header),
            %%{win, Win} = lists:keyfind(win, 1, Header),
            %%{opt, OptBinary} = lists:keyfind(opt, 1, Header),
            %%Opt = pkt_tcp:options(OptBinary),
	    PayloadSize = payloadsize(IP, TCP),
	    Payload = <<PayloadPadded:PayloadSize/binary>>,
	    %% io:format("WorkerPid: ~p, packet ~p~n", [WorkerPid, 
	    %%			      {packet_with_addressing, {Ack, Syn, Fin, Rst, Seqno, Ackno, Win, Opt}, 
            %%		       {{Source_address, Source_port}, {Destination_address, Destination_port}}, 
	    %%		       DLT, Time, Len, Packet, PayloadLength}]),
	    Chksum_ok = case IP of
			    #ipv4{} ->
				IPSum = pkt:makesum(IP),
				TCPSum = pkt:makesum([IP, TCP, Payload]),
				case [IPSum, TCPSum] of 
				    [0,0] ->
					true;
                                    [_,_] ->
					io:format("Wrong checksum: {S:~p,D:~p,P:~p} {IPSum~p, TCPSum~p}~n Packet:~p~nDecoded~w~n", [IP#ipv4.saddr,IP#ipv4.daddr,IP#ipv4.p, IPSum, TCPSum, Packet, pkt:decapsulate({pkt:dlt(DLT), Packet})]),
					false
				end;
			    #ipv6{} ->
				true % checksum not implemented for ipv6 
			end,	    
	    case Chksum_ok of
                true -> 
		    defrag_worker:send_packet(WorkerPid, 
					      {packet_with_addressing, {Ack, Syn, Fin, Rst, Seqno, Ackno, Win, Opt}, 
					       {{Source_address, Sport}, {Destination_address, Dport}}, 
					       DLT, Time, Len, Packet, PayloadSize});
		false ->
		    ok % ignore packet as checksum is not ok			
	    end,
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
    {found, Pid, {{Source_address, Source_port}, {Destination_address, Destination_port}}};
get_connection_worker_pid_by_address_tuple(
  [{{{Destination_address, Destination_port},{Source_address, Source_port}}, Pid}|_AddressTupleElements], 
  {{Source_address, Source_port}, {Destination_address, Destination_port}})->
    {found, Pid, {{Destination_address, Destination_port},{Source_address, Source_port}}};
get_connection_worker_pid_by_address_tuple(
  [_AddressTupleElement|AddressTupleElements], 
  AddressTuple
 )->
    get_connection_worker_pid_by_address_tuple(AddressTupleElements, AddressTuple).

payloadsize(#ipv4{len = Len, hl = HL}, #tcp{off = Off}) ->
    Len - (HL * 4) - (Off * 4);

%% jumbo packet
payloadsize(#ipv6{len = 0, next = _Next}, #tcp{off = _Off}) ->
						% XXX handle jumbo packet here
    io:format("Warning!!! Jumbo packet!!!"),
    0;
payloadsize(#ipv6{len = Len, next = ?IPPROTO_TCP}, #tcp{off = Off}) ->
    Len - (Off * 4);


%% additional extension headeres
payloadsize(#ipv6{len = _Len, next = _Next}, #tcp{off = _Off}) ->
%% XXX handle extension headers here
    io:format("Warning!!! Extension packet!!!"),
    0.


