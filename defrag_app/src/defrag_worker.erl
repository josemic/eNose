
%% Copyright (c) 2009-2013, Michael Santos <michael.santos@gmail.com>
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
%% POSSIBILITY OF SUCH DAMAGE
-module(defrag_worker).

-behaviour(gen_fsm).

%% API
-export([start_link/3,  send_packet/2, stop/1, smaller/2, smaller_or_equal/2]).

%% gen_fsm callbacks
-export([
	 init/1, 
         state_listen/2,
	 state_syn_sent/2,
	 state_syn_received/2,
         state_syn_syn_ack_sent/2,
	 state_established/2,
	 state_fin_wait_1/2,
	 state_fin_wait_2/2,
	 state_fin_fin_wait/2,
	 state_fin_finack_wait/2,	 
         state_fin_ack_fin_wait/2,
 	 state_closing/2,
	 state_time_wait/2,
	 handle_event/3,
	 handle_sync_event/4, 
	 handle_info/3, 
	 terminate/3, 
	 code_change/4]).

-define(SERVER, ?MODULE).

-define(DEBUG_WORKER, true).

-ifdef(DEBUG_WORKER).
%%-define(GEN_FSM_OPTS, {debug, [trace, {log_to_file, "log/defrag/trace_"++Name_s++".log"}]}).
-define(GEN_FSM_OPTS, {debug, [{log_to_file, "log/defrag/trace_"++Name_s++".log"}]}).
%%-define(GEN_FSM_OPTS, {debug, [{install,{Dbg_fun,state}}]}).
%%-define(GEN_FSM_OPTS, {debug, [{install,{Dbg_fun,state}}, {log_to_file, "log/defrag/trace_"++Name_s++".log"}]}).
%%-define(GEN_FSM_OPTS, {debug, [trace]}).
-else.
-define(GEN_FSM_OPTS, []).
-endif.



-record(state, {
	  child_worker_list :: [pid()], 
	  instance::integer(),
          address_tuple::[tuple],
	  syn_ack_received::boolean(),
	  fin_ack_received::boolean(), 
	  initiator_address::[tuple],
          initiator_port::[tuple],
          initiator_RCV_NXT::integer(),
          initiator_SND_UNA::integer(),
          initiator_RCV_WND::integer(),
          responder_address::[tuple],
          responder_port::[tuple],
          responder_RCV_NXT::integer(),
	  responder_SND_UNA::integer(),
          responder_RCV_WND::integer(),
	  close_initiator_address::string(),	
	  close_initiator_port::string(),	
          close_initiator_RCV_NXT::integer(),
          close_initiator_SND_UNA::integer(),
          close_initiator_RCV_WND::integer(),
	  close_responder_address::string(),
	  close_responder_port::string(),
          close_responder_RCV_NXT::integer(),
	  close_responder_SND_UNA::integer(),
          close_responder_RCV_WND::integer(),
          initiator_payload_store::[binary()],
          responder_payload_store::[binary()]
	 }).


%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Creates a gen_fsm process which calls Module:init/1 to
%% initialize. To ensure a synchronized start-up procedure, this
%% function does not return until Module:init/1 has returned.
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link(Instance, {packet_with_addressing, {Ack, Syn, Fin, Rst, SEG_SEQ, SEG_ACK, SEG_WND}, 
            	      AddressTuple, DLT, Time, Len, Packet, _PayloadLength=0}, ChildWorkerList)->
    {{Initiator_address, Initiator_port},{Responder_address, Responder_port}} = AddressTuple, 
    Instance_s = integer_to_list(Instance),
    Ref_s = erlang:ref_to_list(make_ref()),
    Name_s = ?MODULE_STRING ++ "_" ++ Instance_s ++ "_" ++ Ref_s ++ "_" ++ lists:flatten(io_lib:format("~p",[now()])) ++ "_" ++  
	lists:flatten(io_lib:format("~p", [Initiator_address])) ++ ":" ++ 
	lists:flatten(io_lib:format("~p", [Initiator_port])) ++ "_" ++ 
	lists:flatten(io_lib:format("~p", [Responder_address])) ++ ":" ++ 
	lists:flatten(io_lib:format("~p", [Responder_port])),
    Name = list_to_atom (Name_s),
    error_logger:info_report("gen_server:start_link(~p)~n",[[{local, Name},?MODULE,[],[],self()]]),
    Dbg_fun = fun(FuncState, Event, ProcState) -> io:format("~nDebugFun:~n-FuncState:~p~n-Event:~p~n-ProcState:~p~n", [FuncState, Event, ProcState]) end,
    gen_fsm:start_link({local,Name},?MODULE,[Instance, {packet_with_addressing, {Ack, Syn, Fin, Rst, SEG_SEQ, SEG_ACK, SEG_WND}, 
							AddressTuple, DLT, Time, Len, Packet, _PayloadLength=0}, ChildWorkerList],[?GEN_FSM_OPTS]).

stop(WorkerPid) ->
    gen_server:call(WorkerPid, stop_worker).

send_packet(WorkerPid, Message) ->
    gen_fsm:send_event(WorkerPid, Message).


%% This implements the statemachine given in:
%% http://en.wikipedia.org/wiki/File:Tcp_state_diagram_fixed.svg

%%%===================================================================
%%% gen_fsm callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a gen_fsm is started using gen_fsm:start/[3,4] or
%% gen_fsm:start_link/[3,4], this function is called by the new
%% process to initialize.
%%
%% @spec init(Args) -> {ok, StateName, State} |
%%                     {ok, StateName, State, Timeout} |
%%                     ignore |
%%                     {stop, StopReason}
%% @end
%%--------------------------------------------------------------------

init([Instance,{packet_with_addressing, {false, true, false, false, SEG_SEQ, SEG_ACK, SEG_WND}, 
		AddressTuple, 
		DLT, Time, Len, Packet, _PayloadLength=0}, ChildWorkerList]) ->
    {{Initiator_address, Initiator_port},{Responder_address, Responder_port}} = AddressTuple,
    State = #state{
	       instance = Instance, 
	       address_tuple = AddressTuple, 
	       initiator_address = Initiator_address,
	       initiator_port = Initiator_port,
	       responder_address = Responder_address,
	       responder_port = Responder_port,
	       close_initiator_address = undefined,	
	       close_initiator_port = undefined,
	       close_responder_address = undefined,
	       close_responder_port = undefined,
	       child_worker_list = ChildWorkerList,
	       syn_ack_received = false,
               fin_ack_received = false,
               initiator_payload_store = [],
               responder_payload_store = []
	      },
    StateNew1 = storeState_RCV_NXT(initiator, State,     SEG_SEQ+1),
    StateNew2 = storeState_SND_UNA(initiator, StateNew1, SEG_ACK, false),
    StateNew  = storeState_SND_WND(initiator, StateNew2, SEG_WND),
    {ok, state_syn_sent, StateNew}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% There should be one instance of this function for each possible
%% state name. Whenever a gen_fsm receives an event sent using
%% gen_fsm:send_event/2, the instance of this function with the same
%% name as the current state name StateName is called to handle
%% the event. It is also called if a timeout occurs.
%%
%% @spec state_name(Event, State) ->
%%                   {next_state, NextStateName, NextState} |
%%                   {next_state, NextStateName, NextState, Timeout} |
%%                   {stop, Reason, NewState}
%% @end
%%--------------------------------------------------------------------
%%         
%%{packet_with_addressing, 
%%		{Ack, Syn, Fin, Rst, SEG_SEQ, SEG_ACK, SEG_WND}, 
%%		{{Source_address, Source_port},{Destination_address, Destination_port}}, 
%%		DLT, Time, Len, Packet, _PayloadLength=0}),
state_listen( % this state ocurrs only after reset
  {packet_with_addressing, 
   {false, true, false, Rst, SEG_SEQ, SEG_ACK, SEG_WND}, % Syn after Rst
   {{Initiator_address, Initiator_port}, {Responder_address, Responder_port}}, 
   DLT, Time, Len, Packet, _PayloadLength=0}, State) when 
      State#state.responder_address == Responder_address,
      State#state.responder_port == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port == Initiator_port ->
    %% Rst should be ignored // RFC 793, p65
    Direction = initiator,
    case test_sequence_no_in_window(Direction, State, SEG_SEQ) of
	true -> 
	    StateNew1 = storeState_RCV_NXT(Direction, State,     SEG_SEQ+1),
	    StateNew2 = storeState_SND_UNA(Direction, StateNew1, SEG_ACK, false),
	    StateNew  = storeState_SND_WND(Direction, StateNew2, SEG_WND), 
	    NextStateName = state_syn_sent;
	false ->
	    StateNew = State,
	    NextStateName = state_listen
    end,
    {next_state, NextStateName, StateNew};

state_listen(
  {packet_with_addressing,
   {true, _, _, false, SEG_SEQ, SEG_ACK, SEG_WND}, % Ack
   {{_, _},{_,_}}, 
   DLT, Time, Len, Packet, _PayloadLength=0}, State) ->
    %% ignore all Ack packages // RCF 793 p. 65
    {next_state, state_listen, State};

state_listen(
  {packet_with_addressing,
   {{_, _},{_,_}}, 
   DLT, Time, Len, Packet, _PayloadLength}, State) ->
    {next_state, state_listen, State}.


state_syn_sent(
  {packet_with_addressing, 
   {false, true, false, false, SEG_SEQ, SEG_ACK, SEG_WND}, % Syn (when Ack received before)
   {{Responder_address, Responder_port}, {Initiator_address, Initiator_port}}, 
   DLT, Time, Len, Packet, _PayloadLength=0}, State) when
      State#state.syn_ack_received == true, % !!!!!!!! Ack received before
      State#state.responder_address == Responder_address,
      State#state.responder_port == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port == Initiator_port ->
    Direction = responder,
    case test_sequence_no_in_window(Direction, State, SEG_SEQ) of
	true -> 
	    StateNew1 = storeState_RCV_NXT(Direction, State,     SEG_SEQ+1),
	    StateNew2 = storeState_SND_UNA(Direction, StateNew1, SEG_ACK, false),
	    StateNew  = storeState_SND_WND(Direction, StateNew2, SEG_WND),
	    NextStateName = state_syn_sent;
	false ->
	    StateNew = State,
	    NextStateName = state_syn_sent
    end,
    {next_state, NextStateName, StateNew};

state_syn_sent(
  {packet_with_addressing, 
   {true, false, false, false, SEG_SEQ, SEG_ACK, SEG_WND}, % Ack
   {{Responder_address, Responder_port}, {Initiator_address, Initiator_port}}, 
   DLT, Time, Len, Packet, _PayloadLength=0}, State) when
      State#state.responder_address == Responder_address,
      State#state.responder_port == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port == Initiator_port ->
    Direction = responder,

    case test_sequence_no_in_window(Direction, State, SEG_SEQ) of
	true -> 
            StateNew1 = State#state{syn_ack_received = true},     % set flag for received Ack
	    StateNew2 = storeState_RCV_NXT(Direction, StateNew1, SEG_SEQ), % as pure ACK received, sequence number is not increased
	    StateNew3 = storeState_SND_UNA(Direction, StateNew2, SEG_ACK, true),
	    StateNew  = storeState_SND_WND(Direction, StateNew3, SEG_WND),
	    NextStateName = state_syn_sent;
	false ->
	    StateNew = State,
	    NextStateName = state_syn_sent
    end,		
    {next_state, NextStateName, StateNew};

state_syn_sent(
  {packet_with_addressing, 
   {false, true, false, false, SEG_SEQ, SEG_ACK, SEG_WND}, % Syn retransmission
   {{Initiator_address, Initiator_port}, {Responder_address, Responder_port}}, 
   DLT, Time, Len, Packet, _PayloadLength=0}, State) when 
      State#state.responder_address == Responder_address,
      State#state.responder_port == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port == Initiator_port ->
    Direction = initiator,
    case test_sequence_no_in_window(Direction, State, SEG_SEQ) of
	true -> 
	    StateNew1 = storeState_RCV_NXT(Direction, State,     SEG_SEQ+1),
	    StateNew2 = storeState_SND_UNA(Direction, StateNew1, SEG_ACK, false),
	    StateNew  = storeState_SND_WND(Direction, StateNew2, SEG_WND),
	    NextStateName = state_syn_sent;
	false ->
	    StateNew = State,
	    NextStateName = state_syn_sent
    end,
    {next_state, NextStateName, StateNew};

state_syn_sent(
  {packet_with_addressing, 
   {Ack = true, true, false, false, SEG_SEQ, SEG_ACK, SEG_WND}, % Syn-Ack
   {{Responder_address, Responder_port}, {Initiator_address, Initiator_port}}, 
   DLT, Time, Len, Packet, _PayloadLength=0}, State) when 
      State#state.responder_address == Responder_address,
      State#state.responder_port == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port == Initiator_port ->
    Direction = responder,
    case test_sequence_no_in_window(Direction, State, SEG_SEQ) of
	true -> 
	    StateNew1 = storeState_RCV_NXT(Direction, State,     SEG_SEQ+1),
	    StateNew2 = storeState_SND_UNA(Direction, StateNew1, SEG_ACK, Ack),
	    StateNew  = storeState_SND_WND(Direction, StateNew2, SEG_WND),
	    NextStateName = state_syn_syn_ack_sent;
	false ->
	    StateNew = State,
	    NextStateName = state_syn_sent
    end,
    {next_state, NextStateName, StateNew};

state_syn_sent(
  {packet_with_addressing,
   {Ack, false, true, false, SEG_SEQ, SEG_ACK, SEG_WND}, % Fin / Fin-Ack
   {{Initiator_address, Initiator_port}, {Responder_address, Responder_port}}, 
   DLT, Time, Len, Packet, _PayloadLength=0}, State) when 
      State#state.responder_address == Responder_address,
      State#state.responder_port == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port == Initiator_port ->
    Direction = initiator,
    Close_Direction = close_initiator,
    case test_sequence_no_in_window(Direction, State, SEG_SEQ) of
	true -> 
            StateNew1 = copy_state_to_close_initiator_close_responder(Direction, State), 
    	    StateNew2 = storeState_RCV_NXT(Close_Direction, StateNew1, SEG_SEQ+1),
	    StateNew3 = storeState_SND_UNA(Close_Direction, StateNew2, SEG_ACK, Ack),
	    StateNew  = storeState_SND_WND(Close_Direction, StateNew3, SEG_WND),
	    NextStateName = state_fin_wait_1;
        false ->
            StateNew = State,
            NextStateName = state_syn_sent
    end,
    {next_state, NextStateName, StateNew};

state_syn_sent(
  {packet_with_addressing,
   {Ack = false, false, true, false, SEG_SEQ, SEG_ACK, SEG_WND}, % Fin
   {{Responder_address, Responder_port}, {Initiator_address, Initiator_port}}, 
   DLT, Time, Len, Packet, _PayloadLength=0}, State) when 
      State#state.responder_address == Responder_address,
      State#state.responder_port == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port == Initiator_port ->
    Direction = responder,
    Close_Direction = close_initiator,
    case test_sequence_no_in_window(Direction, State, SEG_SEQ) of
	true -> 
            StateNew1 = copy_state_to_close_initiator_close_responder(Direction, State), 
    	    StateNew2 = storeState_RCV_NXT(Close_Direction, StateNew1, SEG_SEQ+1),
	    StateNew3 = storeState_SND_UNA(Close_Direction, StateNew2, SEG_ACK, Ack),
	    StateNew  = storeState_SND_WND(Close_Direction, StateNew3, SEG_WND),
	    NextStateName = state_fin_wait_1;
        false ->
            StateNew = State,
            NextStateName = state_syn_sent
    end,
    {next_state, NextStateName, StateNew};

state_syn_sent(
  {packet_with_addressing,
   {_, _, _, true, SEG_SEQ, SEG_ACK, SEG_WND}, % Rst
   {{_, _},{_,_}}, 
   DLT, Time, Len, Packet, _PayloadLength}, State) ->
    {next_state, state_listen, State, 10000}.

state_syn_syn_ack_sent(
  {packet_with_addressing, 
   {Ack = true, false, false, false, SEG_SEQ, SEG_ACK, SEG_WND}, % Ack
   {{Initiator_address, Initiator_port}, {Responder_address, Responder_port}}, 
   DLT, Time, Len, Packet, _PayloadLength=0}, State) when 
      State#state.responder_address == Responder_address,
      State#state.responder_port == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port == Initiator_port ->
    Direction = initiator,
    case test_sequence_no_in_window(Direction, State, SEG_SEQ) of
	true -> 
	    StateNew1 = storeState_RCV_NXT(Direction, State,     SEG_SEQ), % as pure ACK received, sequence number is not increased
            StateNew2 = storeState_SND_UNA(Direction, StateNew1, SEG_ACK, Ack),
	    StateNew  = storeState_SND_WND(Direction, StateNew2, SEG_WND),
            NextStateName = state_established;
        false ->
            StateNew = State,
            NextStateName = state_syn_syn_ack_sent
    end,
    {next_state, NextStateName, StateNew};

state_syn_syn_ack_sent(
  {packet_with_addressing, 
   {Ack = true, false, false, false, SEG_SEQ, SEG_ACK, SEG_WND}, % Ack retransmission
   {{Responder_address, Responder_port}, {Initiator_address, Initiator_port}}, 
   DLT, Time, Len, Packet, _PayloadLength=0}, State) when 
      State#state.responder_address == Responder_address,
      State#state.responder_port == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port == Initiator_port ->
    Direction = responder,
    case test_sequence_no_in_window(Direction, State, SEG_SEQ) of
	true -> 
	    StateNew1 = storeState_RCV_NXT(Direction, State,     SEG_SEQ), % as pure ACK received, sequence number is not increased
	    StateNew2 = storeState_SND_UNA(Direction, StateNew1, SEG_ACK, Ack),
	    StateNew  = storeState_SND_WND(Direction, StateNew2, SEG_WND),
            NextStateName = state_established;
        false ->
            StateNew = State,
            NextStateName = state_syn_syn_ack_sent
    end,
    {next_state, NextStateName, StateNew};

state_syn_syn_ack_sent(
  {packet_with_addressing,
   {Ack, false, true, false, SEG_SEQ, SEG_ACK, SEG_WND}, % Fin / Fin-Ack
   {{Initiator_address, Initiator_port}, {Responder_address, Responder_port}}, 
   DLT, Time, Len, Packet, _PayloadLength=0}, State) when 
      State#state.responder_address == Responder_address,
      State#state.responder_port == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port == Initiator_port ->
    Direction = initiator,
    Close_Direction = close_initiator,
    case test_sequence_no_in_window(Direction, State, SEG_SEQ) of
	true -> 
            StateNew1 = copy_state_to_close_initiator_close_responder(Direction, State), 
    	    StateNew2 = storeState_RCV_NXT(Close_Direction, StateNew1, SEG_SEQ+1),
	    StateNew3 = storeState_SND_UNA(Close_Direction, StateNew2, SEG_ACK, Ack),
	    StateNew  = storeState_SND_WND(Close_Direction, StateNew3, SEG_WND),
	    NextStateName = state_fin_wait_1;
        false ->
            StateNew = State,
            NextStateName = state_syn_syn_ack_sent
    end,
    {next_state, NextStateName, StateNew};

state_syn_syn_ack_sent(
  {packet_with_addressing,
   {Ack, false, true, false, SEG_SEQ, SEG_ACK, SEG_WND}, % Fin / Fin-Ack
   {{Responder_address, Responder_port}, {Initiator_address, Initiator_port}}, 
   DLT, Time, Len, Packet, _PayloadLength=0}, State) when 
      State#state.responder_address == Responder_address,
      State#state.responder_port == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port == Initiator_port ->
    Direction = responder,
    Close_Direction = close_initiator,
    case test_sequence_no_in_window(Direction, State, SEG_SEQ) of
	true -> 
            StateNew1 = copy_state_to_close_initiator_close_responder(Direction, State), 
    	    StateNew2 = storeState_RCV_NXT(Close_Direction, StateNew1, SEG_SEQ+1),
	    StateNew3 = storeState_SND_UNA(Close_Direction, StateNew2, SEG_ACK, Ack),
	    StateNew  = storeState_SND_WND(Close_Direction, StateNew3, SEG_WND),
	    NextStateName = state_fin_wait_1;
        false ->
            StateNew = State,
            NextStateName = state_syn_syn_ack_sent
    end,
    {next_state, NextStateName, StateNew};


state_syn_syn_ack_sent(
  {packet_with_addressing,
   {_, _, _, true, SEG_SEQ, SEG_ACK, SEG_WND}, % Rst
   {{_, _},{_,_}}, 
   DLT, Time, Len, Packet, _PayloadLength}, State) ->
    {next_state, state_listen, State, 10000}.

state_syn_received(
  {packet_with_addressing, 
   {true, false, false, false, SEG_SEQ, SEG_ACK, SEG_WND}, % Ack
   {{Initiator_address, Initiator_port}, {Responder_address, Responder_port}}, 
   DLT, Time, Len, Packet, _PayloadLength=0}, State) when 
      State#state.responder_address == Responder_address,
      State#state.responder_port == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port == Initiator_port ->
    Direction = initiator,
    case test_sequence_no_in_window(Direction, State, SEG_SEQ) of
	true -> 
	    StateNew1 = storeState_RCV_NXT(Direction, State,     SEG_SEQ), % as pure ACK received, sequence number is not increased
	    StateNew2 = storeState_SND_UNA(Direction, StateNew1, SEG_ACK, true),
	    StateNew  = storeState_SND_WND(Direction, StateNew2, SEG_WND),
	    NextStateName = state_established;
        false ->
            StateNew = State,
            NextStateName = state_established
    end,
    {next_state, NextStateName, StateNew};

state_syn_received(
  {packet_with_addressing,
   {Ack, false, true, false, SEG_SEQ, SEG_ACK, SEG_WND}, % Fin / Fin-Ack
   {{Initiator_address, Initiator_port}, {Responder_address, Responder_port}}, 
   DLT, Time, Len, Packet, _PayloadLength=0}, State) when 
      State#state.responder_address == Responder_address,
      State#state.responder_port == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port == Initiator_port ->
    Direction = initiator,
    Close_Direction = close_initiator,
    case test_sequence_no_in_window(Direction, State, SEG_SEQ) of
	true -> 
            StateNew1 = copy_state_to_close_initiator_close_responder(Direction, State), 
    	    StateNew2 = storeState_RCV_NXT(Close_Direction, StateNew1, SEG_SEQ+1),
	    StateNew3 = storeState_SND_UNA(Close_Direction, StateNew2, SEG_ACK, Ack),
	    StateNew  = storeState_SND_WND(Close_Direction, StateNew3, SEG_WND),
	    NextStateName = state_fin_wait_1;
        false ->
            StateNew = State,
            NextStateName = state_syn_received
    end,
    {next_state, NextStateName, StateNew};

state_syn_received(
  {packet_with_addressing,
   {Ack, false, true, false, SEG_SEQ, SEG_ACK, SEG_WND}, % Fin / Fin-Ack
   {{Responder_address, Responder_port}, {Initiator_address, Initiator_port}}, 
   DLT, Time, Len, Packet, _PayloadLength=0}, State) when 
      State#state.responder_address == Responder_address,
      State#state.responder_port == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port == Initiator_port ->
    Direction = responder,
    Close_Direction = close_initiator,
    case test_sequence_no_in_window(Direction, State, SEG_SEQ) of
	true -> 
            StateNew1 = copy_state_to_close_initiator_close_responder(Direction, State), 
    	    StateNew2 = storeState_RCV_NXT(Close_Direction, StateNew1, SEG_SEQ+1),
	    StateNew3 = storeState_SND_UNA(Close_Direction, StateNew2, SEG_ACK, Ack),
	    StateNew  = storeState_SND_WND(Close_Direction, StateNew3, SEG_WND),
	    NextStateName = state_fin_wait_1;
        false ->
            StateNew = State,
            NextStateName = state_syn_received
    end,
    {next_state, NextStateName, StateNew};

state_syn_received(
  {packet_with_addressing,
   {_, _, _, true, _SEG_SEQ, _SEG_ACK, _SEG_WND}, % Rst
   {{_, _},{_,_}}, 
   DLT, Time, Len, Packet, _PayloadLength}, State) ->
    {next_state, state_listen, State, 10000}.

state_established(
  {packet_with_addressing,
   {Ack = true, false, false, false, SEG_SEQ, SEG_ACK, SEG_WND}, % No payload
   {{Initiator_address, Initiator_port}, {Responder_address, Responder_port}}, 
   DLT, Time, Len, Packet, PayloadLength=0}, State) when 
      State#state.responder_address == Responder_address,
      State#state.responder_port == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port == Initiator_port ->
    [Ether, IP, Hdr, Payload] = epcap_port_lib:decode(pkt:link_type(DLT), Packet),
    Direction = initiator,
    case test_sequence_no_in_window(Direction, State, SEG_SEQ) of
	true -> 
	    StateNew1 = storeState_RCV_NXT(Direction, State,     SEG_SEQ, PayloadLength),
	    StateNew2 = storeState_SND_UNA(Direction, StateNew1, SEG_ACK, PayloadLength, Ack),
	    StateNew  = storeState_SND_WND(Direction, StateNew2, SEG_WND);
        false ->
	    StateNew = State % SEG_ACK should be 0 // RFC 793, p. 65
    end,
    {next_state, state_established, StateNew};

state_established(
  {packet_with_addressing,
   {Ack = true, false, false, false, SEG_SEQ, SEG_ACK, SEG_WND},  % No payload
   {{Responder_address, Responder_port}, {Initiator_address, Initiator_port}}, 
   DLT, Time, Len, Packet, PayloadLength=0}, State) when 
      State#state.responder_address == Responder_address,
      State#state.responder_port == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port == Initiator_port ->
    [Ether, IP, Hdr, Payload] = epcap_port_lib:decode(pkt:link_type(DLT), Packet),
    Direction = responder,
    case test_sequence_no_in_window(Direction, State, SEG_SEQ) of
	true -> 
	    StateNew1 = storeState_RCV_NXT(Direction, State,     SEG_SEQ, PayloadLength),
	    StateNew2 = storeState_SND_UNA(Direction, StateNew1, SEG_ACK, PayloadLength, Ack),
	    StateNew  = storeState_SND_WND(Direction, StateNew2, SEG_WND);
	false ->
	    StateNew = State % SEG_ACK should be 0 // RFC 793, p. 65
    end,
    {next_state, state_established, StateNew};

state_established(
  {packet_with_addressing,
   {Ack, false, false, false, SEG_SEQ, SEG_ACK, SEG_WND}, % payload, Note: if Ack == false, SEG_ACK should be 0
   {{Initiator_address, Initiator_port}, {Responder_address, Responder_port}}, 
   DLT, Time, Len, Packet, PayloadLength}, State) when 
      State#state.responder_address == Responder_address,
      State#state.responder_port == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port == Initiator_port ->
    [Ether, IP, Hdr, Payload] = epcap_port_lib:decode(pkt:link_type(DLT), Packet),
    Direction = initiator,
    case test_sequence_no_in_window(Direction, State, SEG_SEQ, PayloadLength) of
	true -> 
	    StateNew1 = storeState_RCV_NXT(Direction, State,     SEG_SEQ, PayloadLength),
	    StateNew2 = storeState_SND_UNA(Direction, StateNew1, SEG_ACK, PayloadLength, Ack),
	    StateNew3 = storeState_SND_WND(Direction, StateNew2, SEG_WND),
      	    StateNew  = storeState_Payload(Direction, StateNew3, SEG_SEQ, PayloadLength, Payload);
        false ->
	    StateNew = State
    end,
    {next_state, state_established, StateNew};

state_established(
  {packet_with_addressing,
   {Ack, false, false, false, SEG_SEQ, SEG_ACK, SEG_WND},  % payload, Note: if Ack == false, SEG_ACK should be 0
   {{Responder_address, Responder_port}, {Initiator_address, Initiator_port}}, 
   DLT, Time, Len, Packet, PayloadLength}, State) when 
      State#state.responder_address == Responder_address,
      State#state.responder_port == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port == Initiator_port ->
    [_Ether, _IP, _Hdr, Payload] = epcap_port_lib:decode(pkt:link_type(DLT), Packet),
    Direction = responder,
    case test_sequence_no_in_window(Direction, State, SEG_SEQ, PayloadLength) of
	true -> 
	    StateNew1 = storeState_RCV_NXT(Direction, State,     SEG_SEQ, PayloadLength),
	    StateNew2 = storeState_SND_UNA(Direction, StateNew1, SEG_ACK, PayloadLength, Ack),
	    StateNew3 = storeState_SND_WND(Direction, StateNew2, SEG_WND),
      	    StateNew  = storeState_Payload(Direction, StateNew3, SEG_SEQ, PayloadLength, Payload);
	false ->
	    StateNew = State 
    end,
    {next_state, state_established, StateNew};

state_established(
  {packet_with_addressing,
   {true, true, false, false, SEG_SEQ, SEG_ACK, SEG_WND},  % Syn-Ack retransmission
   {{Initiator_address, Initiator_port}, {Responder_address, Responder_port}}, 
   DLT, Time, Len, Packet, _PayloadLength=0}, State) when 
      State#state.responder_address == Responder_address,
      State#state.responder_port == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port == Initiator_port ->
    Direction = initiator,
    case test_sequence_no_in_window(Direction, State, SEG_SEQ) of
	true -> 
	    StateNew1 = storeState_RCV_NXT(Direction, State,     SEG_SEQ+1),
	    StateNew2 = storeState_SND_UNA(Direction, StateNew1, SEG_ACK, true),
	    StateNew  = storeState_SND_WND(Direction, StateNew2, SEG_WND);
        false ->
            StateNew = State
    end,
    {next_state, state_established, StateNew};

state_established(
  {packet_with_addressing,
   {true, true, false, false, SEG_SEQ, SEG_ACK, SEG_WND}, % Syn-Ack retransmission
   {{Responder_address, Responder_port}, {Initiator_address, Initiator_port}}, 
   DLT, Time, Len, Packet, _PayloadLength=0}, State) when 
      State#state.responder_address == Responder_address,
      State#state.responder_port == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port == Initiator_port ->
    Direction = responder,
    case test_sequence_no_in_window(Direction, State, SEG_SEQ) of
	true -> 
	    StateNew1 = storeState_RCV_NXT(Direction, State,     SEG_SEQ+1),
	    StateNew2 = storeState_SND_UNA(Direction, StateNew1, SEG_ACK, true),
	    StateNew  = storeState_SND_WND(Direction, StateNew2, SEG_WND);
        false ->
            StateNew = State
    end,
    {next_state, state_established, StateNew};

state_established(
  {packet_with_addressing,
   {Ack = true, false, false, false, SEG_SEQ, SEG_ACK, SEG_WND}, % Ack without payload, Note: SEG_SEQ should be 0
   {{Initiator_address, Initiator_port}, {Responder_address, Responder_port}}, 
   DLT, Time, Len, Packet, _PayloadLength=0}, State) when 
      State#state.responder_address == Responder_address,
      State#state.responder_port == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port == Initiator_port ->
    Direction = initiator,
    case test_sequence_no_in_window(Direction, State, SEG_SEQ) of
	true -> 
	    StateNew1 = storeState_RCV_NXT(Direction, State,     SEG_SEQ), % as pure ACK received, sequence number is not increased
	    StateNew2 = storeState_SND_UNA(Direction, StateNew1, SEG_ACK, Ack),
	    StateNew  = storeState_SND_WND(Direction, StateNew2, SEG_WND);
        false ->
            StateNew = State
    end,
    {next_state, state_established, StateNew};

state_established(
  {packet_with_addressing,
   {Ack = true, false, false, false, SEG_SEQ, SEG_ACK, SEG_WND}, % Ack without payload, Note: SEG_SEQ should be 0
   {{Responder_address, Responder_port}, {Initiator_address, Initiator_port}}, 
   DLT, Time, Len, Packet, _PayloadLength=0}, State) when 
      State#state.responder_address == Responder_address,
      State#state.responder_port == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port == Initiator_port ->
    Direction = responder,
    case test_sequence_no_in_window(Direction, State, SEG_SEQ) of
	true -> 
	    StateNew1 = storeState_RCV_NXT(Direction, State,     SEG_SEQ), % as pure ACK received, sequence number is not increased
	    StateNew2 = storeState_SND_UNA(Direction, StateNew1, SEG_ACK, Ack),
	    StateNew  = storeState_SND_WND(Direction, StateNew2, SEG_WND);
        false ->
            StateNew = State
    end,
    {next_state, state_established, StateNew};

state_established(
  {packet_with_addressing,
   {Ack, false, true, false, SEG_SEQ, SEG_ACK, SEG_WND}, % Fin / Fin-Ack
   {{Initiator_address, Initiator_port}, {Responder_address, Responder_port}}, 
   DLT, Time, Len, Packet, _PayloadLength=0}, State) when 
      State#state.responder_address == Responder_address,
      State#state.responder_port == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port == Initiator_port ->
    Direction = initiator,
    Close_Direction = close_initiator,
    case test_sequence_no_in_window(Direction, State, SEG_SEQ) of
	true -> 
            StateNew1 = copy_state_to_close_initiator_close_responder(Direction, State), 
    	    StateNew2 = storeState_RCV_NXT(Close_Direction, StateNew1, SEG_SEQ+1),
	    StateNew3 = storeState_SND_UNA(Close_Direction, StateNew2, SEG_ACK, Ack),
	    StateNew  = storeState_SND_WND(Close_Direction, StateNew3, SEG_WND),
	    NextStateName = state_fin_wait_1;
        false ->
            StateNew = State,
            NextStateName = state_established,
            io:format("Warning!!!!"),
            log_close_initiator_close_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew)
    end,
    {next_state, NextStateName, StateNew};

state_established(
  {packet_with_addressing,
   {Ack, false, true, false, SEG_SEQ, SEG_ACK, SEG_WND}, % Fin / Fin-Ack 
   {{Responder_address, Responder_port}, {Initiator_address, Initiator_port}}, 
   DLT, Time, Len, Packet, _PayloadLength=0}, State) when 
      State#state.responder_address == Responder_address,
      State#state.responder_port == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port == Initiator_port ->
    Direction = responder,
    Close_Direction = close_initiator,
    case test_sequence_no_in_window(Direction, State, SEG_SEQ) of
	true -> 
            StateNew1 = copy_state_to_close_initiator_close_responder(Direction, State), 
    	    StateNew2 = storeState_RCV_NXT(Close_Direction, StateNew1, SEG_SEQ+1),
	    StateNew3 = storeState_SND_UNA(Close_Direction, StateNew2, SEG_ACK, Ack),
	    StateNew  = storeState_SND_WND(Close_Direction, StateNew3, SEG_WND),
	    NextStateName = state_fin_wait_1;
        false ->
            StateNew = State,
            NextStateName = state_established,
            io:format("Warning!!!!"),
            log_close_initiator_close_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew)
    end,
    {next_state, NextStateName, StateNew};

state_established(
  {packet_with_addressing,
   {_, _, _, true, SEG_SEQ, SEG_ACK, SEG_WND}, % Rst
   {{_, _},{_,_}}, 
   DLT, Time, Len, Packet, _PayloadLength}, State) ->
    {next_state, state_time_wait, State, 10000}.

state_fin_wait_1(
  {packet_with_addressing,
   {Ack = true, false, true, false, SEG_SEQ, SEG_ACK, SEG_WND}, % Fin-Ack
   {{Close_responder_address, Close_responder_port}, 
    {Close_initiator_address, Close_initiator_port}}, 
   DLT, Time, Len, Packet, _PayloadLength=0}, State) when 
      State#state.close_responder_address == Close_responder_address, 
      State#state.close_responder_port    == Close_responder_port,
      State#state.close_initiator_address == Close_initiator_address,
      State#state.close_initiator_port    == Close_initiator_port ->
    Close_Direction = close_responder,
    case test_sequence_no_in_window(Close_Direction, State, SEG_SEQ) of
	true -> 
    	    StateNew1 = storeState_RCV_NXT(Close_Direction, State    , SEG_SEQ+1),
	    StateNew2 = storeState_SND_UNA(Close_Direction, StateNew1, SEG_ACK, Ack),
	    StateNew  = storeState_SND_WND(Close_Direction, StateNew2, SEG_WND),
	    NextStateName = state_fin_finack_wait,
            log_close_initiator_close_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew);
        false ->
            StateNew = State,
            NextStateName = state_fin_wait_1, 
            log_close_initiator_close_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew)
    end,
    {next_state, NextStateName, StateNew};

state_fin_wait_1(
  {packet_with_addressing,
   {Ack= true, false, true, false, SEG_SEQ, SEG_ACK, SEG_WND}, % Fin-Ack retransmission
   {{Close_initiator_address, Close_initiator_port}, 
    {Close_responder_address, Close_responder_port}}, 
   DLT, Time, Len, Packet, _PayloadLength=0}, State) when 
      State#state.close_responder_address == Close_responder_address, 
      State#state.close_responder_port    == Close_responder_port,
      State#state.close_initiator_address == Close_initiator_address,
      State#state.close_initiator_port    == Close_initiator_port ->
    Close_Direction = close_initiator,
    case test_sequence_no_in_window(Close_Direction, State, SEG_SEQ) of
	true -> 
	    StateNew1 = storeState_RCV_NXT(Close_Direction, State    , SEG_SEQ+1),
	    StateNew2 = storeState_SND_UNA(Close_Direction, StateNew1, SEG_ACK, Ack),
	    StateNew  = storeState_SND_WND(Close_Direction, StateNew2, SEG_WND),
	    NextStateName = state_fin_wait_1, 
            log_close_initiator_close_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew);
	false ->
	    StateNew = State,
	    NextStateName = state_fin_wait_1,
            log_close_initiator_close_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew)
    end,
    {next_state, NextStateName, StateNew};

state_fin_wait_1(
  {packet_with_addressing,
   {Ack = true, false, false, false, SEG_SEQ, SEG_ACK, SEG_WND}, % Ack 
   {{Close_responder_address, Close_responder_port}, 
    {Close_initiator_address, Close_initiator_port}}, 
   DLT, Time, Len, Packet, _PayloadLength=0}, State) when 
      State#state.close_responder_address == Close_responder_address, 
      State#state.close_responder_port    == Close_responder_port,
      State#state.close_initiator_address == Close_initiator_address,
      State#state.close_initiator_port    == Close_initiator_port ->
    Close_Direction = close_responder,
    case test_sequence_no_in_window(Close_Direction, State, SEG_SEQ) of
	true -> 
	    StateNew1 = State#state{fin_ack_received = true}, % Ack for Fin received 
	    StateNew2 = storeState_RCV_NXT(Close_Direction, StateNew1, SEG_SEQ), % as pure ACK received, sequence number is not increased
	    StateNew3 = storeState_SND_UNA(Close_Direction, StateNew2, SEG_ACK, Ack),
	    StateNew  = storeState_SND_WND(Close_Direction, StateNew3, SEG_WND),
	    NextStateName = state_fin_wait_2,
            log_close_initiator_close_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew);
	false ->
	    StateNew = State,
	    NextStateName = state_fin_wait_1,
            log_close_initiator_close_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew)
    end,
    {next_state, NextStateName, StateNew};

state_fin_wait_1(
  {packet_with_addressing,
   {Ack = true, false, false, false, SEG_SEQ, SEG_ACK, SEG_WND}, % unexpected Ack
   {{Close_initiator_address, Close_initiator_port},
    {Close_responder_address, Close_responder_port}}, 
   DLT, Time, Len, Packet, _PayloadLength=0}, State) when 
      State#state.close_responder_address == Close_responder_address, 
      State#state.close_responder_port    == Close_responder_port,
      State#state.close_initiator_address == Close_initiator_address,
      State#state.close_initiator_port    == Close_initiator_port ->
    Close_Direction = close_responder,
    case test_sequence_no_in_window(Close_Direction, State, SEG_SEQ) of
	true -> 
	    StateNew1 = storeState_RCV_NXT(Close_Direction, State    , SEG_SEQ), % as pure ACK received, sequence number is not increased
	    StateNew2 = storeState_SND_UNA(Close_Direction, StateNew1, SEG_ACK, Ack),
	    StateNew  = storeState_SND_WND(Close_Direction, StateNew2, SEG_WND),
	    NextStateName = state_fin_wait_1,
            log_close_initiator_close_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew);
	false ->
	    StateNew = State,
	    NextStateName = state_fin_wait_1,
            log_close_initiator_close_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew)
    end,
    {next_state, NextStateName, StateNew};

state_fin_wait_1(
  {packet_with_addressing,
   {Ack=false, false, true, false, SEG_SEQ, SEG_ACK, SEG_WND}, % Fin
   {{Close_responder_address, Close_responder_port}, 
    {Close_initiator_address, Close_initiator_port}},
   DLT, Time, Len, Packet, _PayloadLength=0}, State) when 
      State#state.fin_ack_received == true, % when Ack for Fin has been received before
      State#state.close_responder_address == Close_responder_address, 
      State#state.close_responder_port    == Close_responder_port,
      State#state.close_initiator_address == Close_initiator_address,
      State#state.close_initiator_port    == Close_initiator_port ->
    Close_Direction = close_responder,
    case test_sequence_no_in_window(Close_Direction, State, SEG_SEQ) of
	true -> 
	    StateNew1 = storeState_RCV_NXT(Close_Direction, State    , SEG_SEQ+1),
	    StateNew2 = storeState_SND_UNA(Close_Direction, StateNew1, SEG_ACK, Ack),
	    StateNew  = storeState_SND_WND(Close_Direction, StateNew2, SEG_WND),
	    NextStateName = state_fin_fin_wait,
            log_close_initiator_close_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew);
	false ->
	    StateNew = State,
	    NextStateName = state_fin_wait_1,
            log_close_initiator_close_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew)
    end,
    {next_state, NextStateName, StateNew};

state_fin_wait_1(
  {packet_with_addressing,
   {Ack=false, false, true, false, SEG_SEQ, SEG_ACK, SEG_WND}, % Fin
   {{Close_responder_address, Close_responder_port}, 
    {Close_initiator_address, Close_initiator_port}},
   DLT, Time, Len, Packet, _PayloadLength=0}, State) when 
      State#state.fin_ack_received == false, % when Ack for Fin has not been received before
      State#state.close_responder_address == Close_responder_address, 
      State#state.close_responder_port    == Close_responder_port,
      State#state.close_initiator_address == Close_initiator_address,
      State#state.close_initiator_port    == Close_initiator_port ->
    Close_Direction = close_responder,
    case test_sequence_no_in_window(Close_Direction, State, SEG_SEQ) of
	true -> 
	    StateNew1 = storeState_RCV_NXT(Close_Direction, State    , SEG_SEQ+1),
	    StateNew2 = storeState_SND_UNA(Close_Direction, StateNew1, SEG_ACK, Ack),
	    StateNew  = storeState_SND_WND(Close_Direction, StateNew2, SEG_WND),
	    NextStateName = state_closing,
            log_close_initiator_close_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew);
	false ->
	    StateNew = State,
	    NextStateName = state_fin_wait_1,
            log_close_initiator_close_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew)
    end,
    {next_state, NextStateName, StateNew};

state_fin_wait_1(
  {packet_with_addressing,
   {Ack, _, _Fin = true, _, SEG_SEQ, SEG_ACK, SEG_WND}, %% Payload, not expected here as Fin-bit is set
   {{Close_responder_address, Close_responder_port}, 
    {Close_initiator_address, Close_initiator_port}}, 
   DLT, Time, Len, Packet, PayloadLength}, State) when 
      PayloadLength /= 0, % Payload not empty!!!
      State#state.close_responder_address == Close_responder_address, 
      State#state.close_responder_port    == Close_responder_port,
      State#state.close_initiator_address == Close_initiator_address,
      State#state.close_initiator_port    == Close_initiator_port  ->
    io:format("Bad request Fin:true, Ack:~p with Payload~n", [Ack]),
    {next_state, state_time_wait, State, 10000};

state_fin_wait_1(
  {packet_with_addressing,
   {_, _, _, _Rst = true, SEG_SEQ, SEG_ACK, SEG_WND}, %% Payload, not expected here as closed by peer side 
   %%(race condition)!!! - ignore it
   {{Close_responder_address, Close_responder_port}, 
    {Close_initiator_address, Close_initiator_port}}, 
   DLT, Time, Len, Packet, PayloadLength}, State) when 
      PayloadLength /= 0, % Payload not empty!!!
      State#state.close_responder_address == Close_responder_address, 
      State#state.close_responder_port    == Close_responder_port,
      State#state.close_initiator_address == Close_initiator_address,
      State#state.close_initiator_port    == Close_initiator_port  ->
    io:format("Bad request Reset with payload~n"),
    {next_state, state_time_wait, State, 10000};

state_fin_wait_1(
  {packet_with_addressing,
   {_, _, _, _Rst = true, SEG_SEQ, SEG_ACK, SEG_WND}, % Rst
   {{_, _},{_,_}}, 
   DLT, Time, Len, Packet, _PayloadLength}, State) ->
    log_close_initiator_close_responder(state_time_wait, SEG_SEQ, SEG_ACK, SEG_WND, State),
    {next_state, state_time_wait, State, 10000}.

state_fin_wait_2(
  {packet_with_addressing,
   {Ack = true, false, false, false, SEG_SEQ, SEG_ACK, SEG_WND}, % Ack retransmission
   {{Close_responder_address, Close_responder_port},
    {Close_initiator_address, Close_initiator_port}}, 
   DLT, Time, Len, Packet, _PayloadLength=0}, State) when 
      State#state.close_responder_address == Close_responder_address, 
      State#state.close_responder_port    == Close_responder_port,
      State#state.close_initiator_address == Close_initiator_address,
      State#state.close_initiator_port    == Close_initiator_port ->
    Close_Direction = close_responder,
    case test_sequence_no_in_window(Close_Direction, State, SEG_SEQ) of
	true -> 
    	    StateNew1 = storeState_RCV_NXT(Close_Direction, State    , SEG_SEQ+1),
	    StateNew2 = storeState_SND_UNA(Close_Direction, StateNew1, SEG_ACK, Ack),
	    StateNew  = storeState_SND_WND(Close_Direction, StateNew2, SEG_WND), 
	    NextStateName = state_fin_wait_2;
        false ->
            StateNew = State,
            NextStateName = state_fin_wait_2
    end,
    {next_state, NextStateName, StateNew};

state_fin_wait_2(
  {packet_with_addressing,
   {Ack = true, false, true, false, SEG_SEQ, SEG_ACK, SEG_WND}, % Fin-Ack retransmission
   {{Close_initiator_address, Close_initiator_port},
    {Close_responder_address, Close_responder_port}}, 
   DLT, Time, Len, Packet, _PayloadLength=0}, State) when 
      State#state.close_responder_address == Close_responder_address, 
      State#state.close_responder_port    == Close_responder_port,
      State#state.close_initiator_address == Close_initiator_address,
      State#state.close_initiator_port    == Close_initiator_port ->
    Close_Direction = close_initiator,
    case test_sequence_no_in_window(Close_Direction, State, SEG_SEQ) of
	true -> 
    	    StateNew1 = storeState_RCV_NXT(Close_Direction, State    , SEG_SEQ+1),
	    StateNew2 = storeState_SND_UNA(Close_Direction, StateNew1, SEG_ACK, Ack),
	    StateNew  = storeState_SND_WND(Close_Direction, StateNew2, SEG_WND),
	    NextStateName = state_fin_wait_2;
        false ->
            StateNew = State,
            NextStateName = state_fin_wait_2
    end,
    {next_state, NextStateName, StateNew};

state_fin_wait_2(
  {packet_with_addressing,
   {Ack = false, false, true, false, SEG_SEQ, SEG_ACK, SEG_WND}, % Fin
   {{Close_responder_address, Close_responder_port},
    {Close_initiator_address, Close_initiator_port}}, 
   DLT, Time, Len, Packet, _PayloadLength=0}, State) when 
      State#state.close_responder_address == Close_responder_address, 
      State#state.close_responder_port    == Close_responder_port,
      State#state.close_initiator_address == Close_initiator_address,
      State#state.close_initiator_port    == Close_initiator_port ->
    Close_Direction = close_responder,
    case test_sequence_no_in_window(Close_Direction, State, SEG_SEQ) of
	true -> 
    	    StateNew1 = storeState_RCV_NXT(Close_Direction, State    , SEG_SEQ+1),
	    StateNew2 = storeState_SND_UNA(Close_Direction, StateNew1, SEG_ACK, Ack),
	    StateNew  = storeState_SND_WND(Close_Direction, StateNew2, SEG_WND),
            NextStateName = state_fin_ack_fin_wait; 
	false ->
	    StateNew = State,
	    NextStateName = state_fin_wait_2
    end,
    {next_state, NextStateName, StateNew};

state_fin_wait_2(
  {packet_with_addressing,
   {Ack = true, false, _Fin = true, false, SEG_SEQ, SEG_ACK, SEG_WND}, % Fin-Ack
   {{Close_responder_address, Close_responder_port},
    {Close_initiator_address, Close_initiator_port}}, 
   DLT, Time, Len, Packet, _PayloadLength=0}, State) when 
      State#state.close_responder_address == Close_responder_address, 
      State#state.close_responder_port    == Close_responder_port,
      State#state.close_initiator_address == Close_initiator_address,
      State#state.close_initiator_port    == Close_initiator_port ->
    Close_Direction = close_responder,
    case test_sequence_no_in_window(Close_Direction, State, SEG_SEQ) of
	true -> 
    	    StateNew1 = storeState_RCV_NXT(Close_Direction, State    , SEG_SEQ+1),
	    StateNew2 = storeState_SND_UNA(Close_Direction, StateNew1, SEG_ACK, Ack),
	    StateNew  = storeState_SND_WND(Close_Direction, StateNew2, SEG_WND),
            NextStateName = state_fin_ack_fin_wait; 
	false ->
	    StateNew = State,
	    NextStateName = state_fin_wait_2
    end,
    {next_state, NextStateName, StateNew};

state_fin_wait_2(
  {packet_with_addressing,
   {_, _, _, true, _SEG_SEQ, _SEG_ACK, _SEG_WND}, % Rst
   {{_, _},{_,_}}, 
   DLT, Time, Len, Packet, _PayloadLength}, State) ->
    {next_state, state_time_wait, State, 10000}.

state_fin_fin_wait(
  {packet_with_addressing,
   {Ack = true, false, false, false, SEG_SEQ, SEG_ACK, SEG_WND}, % Ack
   {{Close_initiator_address, Close_initiator_port},
    {Close_responder_address, Close_responder_port}}, 
   DLT, Time, Len, Packet, _PayloadLength=0}, State) when 
      State#state.close_responder_address == Close_responder_address, 
      State#state.close_responder_port    == Close_responder_port,
      State#state.close_initiator_address == Close_initiator_address,
      State#state.close_initiator_port    == Close_initiator_port ->
    Close_Direction = close_initiator,
    case test_sequence_no_in_window(Close_Direction, State, SEG_SEQ) of
	true -> 
    	    StateNew1 = storeState_RCV_NXT(Close_Direction, State    , SEG_SEQ), % as pure ACK received, sequence number is not increased
	    StateNew2 = storeState_SND_UNA(Close_Direction, StateNew1, SEG_ACK, Ack),
	    StateNew  = storeState_SND_WND(Close_Direction, StateNew2, SEG_WND),
	    NextStateName = state_closing; 
	false ->
	    StateNew = State,
	    NextStateName = state_fin_fin_wait
    end,
    {next_state, NextStateName, StateNew};

state_fin_fin_wait(
  {packet_with_addressing,
   {_, _, _, true, SEG_SEQ, SEG_ACK, SEG_WND}, % Rst
   {{_, _},{_,_}}, 
   DLT, Time, Len, Packet, _PayloadLength}, State) ->
    {next_state, state_time_wait, State, 10000}.

state_fin_finack_wait(
  {packet_with_addressing,
   {Ack = true, false, false, false, SEG_SEQ, SEG_ACK, SEG_WND}, % Ack
   {{Close_initiator_address, Close_initiator_port},
    {Close_responder_address, Close_responder_port}},
   DLT, Time, Len, Packet, _PayloadLength=0}, State) when 
      State#state.close_responder_address == Close_responder_address, 
      State#state.close_responder_port    == Close_responder_port,
      State#state.close_initiator_address == Close_initiator_address,
      State#state.close_initiator_port    == Close_initiator_port ->
    Close_Direction = close_initiator,
    case test_sequence_no_in_window(Close_Direction, State, SEG_SEQ) of
	true -> 
    	    StateNew1 = storeState_RCV_NXT(Close_Direction, State    , SEG_SEQ), % as pure ACK received, sequence number is not increased
	    StateNew2 = storeState_SND_UNA(Close_Direction, StateNew1, SEG_ACK, Ack),
	    StateNew  = storeState_SND_WND(Close_Direction, StateNew2, SEG_WND),
            {next_state, state_time_wait, StateNew, 10000};
        false ->
            StateNew = State,
            {next_state, state_fin_finack_wait, StateNew}
    end;

state_fin_finack_wait(
  {packet_with_addressing,
   {_, _, _, true, SEG_SEQ, SEG_ACK, SEG_WND}, % Rst
   {{_, _},{_,_}}, 
   DLT, Time, Len, Packet, _PayloadLength}, State) ->
    {next_state, state_time_wait, State, 10000}.

state_fin_ack_fin_wait(
  {packet_with_addressing,
   {Ack = true, false, false, false, SEG_SEQ, SEG_ACK, SEG_WND}, % Ack
   {{Close_initiator_address, Close_initiator_port},
    {Close_responder_address, Close_responder_port}},
   DLT, Time, Len, Packet, _PayloadLength=0}, State) when 
      State#state.close_responder_address == Close_responder_address, 
      State#state.close_responder_port    == Close_responder_port,
      State#state.close_initiator_address == Close_initiator_address,
      State#state.close_initiator_port    == Close_initiator_port ->
    Close_Direction = close_initiator,
    case test_sequence_no_in_window(Close_Direction, State, SEG_SEQ) of
	true -> 
    	    StateNew1 = storeState_RCV_NXT(Close_Direction, State    , SEG_SEQ), % as pure ACK received, sequence number is not increased
	    StateNew2 = storeState_SND_UNA(Close_Direction, StateNew1, SEG_ACK, Ack),
	    StateNew  = storeState_SND_WND(Close_Direction, StateNew2, SEG_WND),
            {next_state, state_time_wait, StateNew, 1000};
        false ->
            StateNew = State,
            {next_state, fin_ack_fin_wait, StateNew}
    end;

state_fin_ack_fin_wait(
  {packet_with_addressing,
   {_, _, _, true, _SEG_SEQ, _SEG_ACK, _SEG_WND}, % Rst
   {{_, _},{_,_}}, 
   DLT, Time, Len, Packet, _PayloadLength}, State) ->
    {next_state, state_time_wait, State, 10000}.

state_closing(
  {packet_with_addressing,
   {Ack = true, false, false, false, SEG_SEQ, SEG_ACK, SEG_WND}, % Ack
   {{Close_initiator_address, Close_initiator_port},
    {Close_responder_address, Close_responder_port}},
   DLT, Time, Len, Packet, _PayloadLength=0}, State) when 
      State#state.close_responder_address == Close_responder_address, 
      State#state.close_responder_port    == Close_responder_port,
      State#state.close_initiator_address == Close_initiator_address,
      State#state.close_initiator_port    == Close_initiator_port ->
    Close_Direction = close_initiator,
    case test_sequence_no_in_window(Close_Direction, State, SEG_SEQ) of
	true -> 
    	    StateNew1 = storeState_RCV_NXT(Close_Direction, State    , SEG_SEQ), % as pure ACK received, sequence number is not increased
	    StateNew2 = storeState_SND_UNA(Close_Direction, StateNew1, SEG_ACK, Ack),
	    StateNew  = storeState_SND_WND(Close_Direction, StateNew2, SEG_WND),
	    NextStateName = state_closing,
            {next_state, NextStateName, StateNew}; 
	false ->
	    StateNew = State,
	    NextStateName = state_time_wait,
	    {next_state, NextStateName, StateNew, 10000}
    end;

state_closing(
  {packet_with_addressing,
   {_, _, _, true, _SEG_SEQ, _SEG_ACK, _SEG_WND}, % Rst
   {{_, _},{_, _}}, 
   DLT, Time, Len, Packet, _PayloadLength}, State) ->
    {next_state, state_time_wait, State, 10000}.

state_time_wait(
  {packet_with_addressing,
   {Ack = true, false, false, false, SEG_SEQ, SEG_ACK, SEG_WND}, % Ack retransmission
   {{Close_responder_address, Close_responder_port},
    {Close_initiator_address, Close_initiator_port}},
   DLT, Time, Len, Packet, _PayloadLength=0}, State) when 
      State#state.close_responder_address == Close_responder_address, 
      State#state.close_responder_port    == Close_responder_port,
      State#state.close_initiator_address == Close_initiator_address,
      State#state.close_initiator_port    == Close_initiator_port ->
    Close_Direction = close_responder,
    case test_sequence_no_in_window(Close_Direction, State, SEG_SEQ) of
	true -> 
    	    StateNew1 = storeState_RCV_NXT(Close_Direction, State    , SEG_SEQ), % as pure ACK received, sequence number is not increased
	    StateNew2 = storeState_SND_UNA(Close_Direction, StateNew1, SEG_ACK, Ack),
	    StateNew  = storeState_SND_WND(Close_Direction, StateNew2, SEG_WND),
            NextStateName = state_time_wait;
	false ->
	    StateNew = State,
	    NextStateName = state_time_wait
    end,
    {next_state, NextStateName, StateNew, 10000}; 

state_time_wait(
  {packet_with_addressing,
   {Ack = true, false, true, false, SEG_SEQ, SEG_ACK, SEG_WND}, % Fin-Ack retransmission
   {{Close_responder_address, Close_responder_port}, 
    {Close_initiator_address, Close_initiator_port}}, 
   DLT, Time, Len, Packet, _PayloadLength=0}, State) when 
      State#state.close_responder_address == Close_responder_address, 
      State#state.close_responder_port    == Close_responder_port,
      State#state.close_initiator_address == Close_initiator_address,
      State#state.close_initiator_port    == Close_initiator_port ->
    Close_Direction = close_responder,
    case test_sequence_no_in_window(Close_Direction, State, SEG_SEQ) of
	true -> 
    	    StateNew1 = storeState_RCV_NXT(Close_Direction, State    , SEG_SEQ+1),
	    StateNew2 = storeState_SND_UNA(Close_Direction, StateNew1, SEG_ACK, Ack),
	    StateNew  = storeState_SND_WND(Close_Direction, StateNew2, SEG_WND),
	    NextStateName = state_time_wait; 
	false ->
	    StateNew = State,
	    NextStateName = state_time_wait
    end,
    {next_state, NextStateName, StateNew, 10000};

state_time_wait(
  {packet_with_addressing,
   {Ack = true, false, false, false, SEG_SEQ, SEG_ACK, SEG_WND}, %Ack
   {{Close_initiator_address, Close_initiator_port},
    {Close_responder_address, Close_responder_port}},
   DLT, Time, Len, Packet, _PayloadLength=0}, State) when 
      State#state.close_responder_address == Close_responder_address, 
      State#state.close_responder_port    == Close_responder_port,
      State#state.close_initiator_address == Close_initiator_address,
      State#state.close_initiator_port    == Close_initiator_port ->
    Close_Direction = close_initiator,
    case test_sequence_no_in_window(Close_Direction, State, SEG_SEQ) of
	true -> 
    	    StateNew1 = storeState_RCV_NXT(Close_Direction, State    , SEG_SEQ), % as pure ACK received, sequence number is not increased
	    StateNew2 = storeState_SND_UNA(Close_Direction, StateNew1, SEG_ACK, Ack),
	    StateNew  = storeState_SND_WND(Close_Direction, StateNew2, SEG_WND),
            NextStateName = state_time_wait;
	false ->
	    StateNew = State,
	    NextStateName = state_time_wait
    end,
    {next_state, NextStateName, StateNew, 10000};

state_time_wait(
  {packet_with_addressing,
   {_, _, _, true, _SEG_SEQ, _SEG_ACK, _SEG_WND}, % Rst
   {{_, _},{_,_}}, 
   DLT, Time, Len, Packet, _PayloadLength}, State) ->
    {next_state, state_time_wait, State, 10000};

state_time_wait(timeout, State) ->
    {stop, shutdown, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% There should be one instance of this function for each possible
%% state name. Whenever a gen_fsm receives an event sent using
%% gen_fsm:sync_send_event/[2,3], the instance of this function with
%% the same name as the current state name StateName is called to
%% handle the event.
%%
%% @spec state_name(Event, From, State) ->
%%                   {next_state, NextStateName, NextState} |
%%                   {next_state, NextStateName, NextState, Timeout} |
%%                   {reply, Reply, NextStateName, NextState} |
%%                   {reply, Reply, NextStateName, NextState, Timeout} |
%%                   {stop, Reason, NewState} |
%%                   {stop, Reason, Reply, NewState}
%% @end
%%--------------------------------------------------------------------
%%state_name(_Event, _From, State) ->
%%    Reply = ok,
%%    {reply, Reply, state_name, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a gen_fsm receives an event sent using
%% gen_fsm:send_all_state_event/2, this function is called to handle
%% the event.
%%
%% @spec handle_event(Event, StateName, State) ->
%%                   {next_state, NextStateName, NextState} |
%%                   {next_state, NextStateName, NextState, Timeout} |
%%                   {stop, Reason, NewState}
%% @end
%%--------------------------------------------------------------------
handle_event(_Event, StateName, State) ->
    {next_state, StateName, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a gen_fsm receives an event sent using
%% gen_fsm:sync_send_all_state_event/[2,3], this function is called
%% to handle the event.
%%
%% @spec handle_sync_event(Event, From, StateName, State) ->
%%                   {next_state, NextStateName, NextState} |
%%                   {next_state, NextStateName, NextState, Timeout} |
%%                   {reply, Reply, NextStateName, NextState} |
%%                   {reply, Reply, NextStateName, NextState, Timeout} |
%%                   {stop, Reason, NewState} |
%%                   {stop, Reason, Reply, NewState}
%% @end
%%--------------------------------------------------------------------
handle_sync_event(_Event, _From, StateName, State) ->
    Reply = ok,
    {reply, Reply, StateName, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_fsm when it receives any
%% message other than a synchronous or asynchronous event
%% (or a system message).
%%
%% @spec handle_info(Info,StateName,State)->
%%                   {next_state, NextStateName, NextState} |
%%                   {next_state, NextStateName, NextState, Timeout} |
%%                   {stop, Reason, NewState}
%% @end
%%--------------------------------------------------------------------
handle_info(_Info, StateName, State) ->
    {next_state, StateName, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_fsm when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_fsm terminates with
%% Reason. The return value is ignored.
%%
%% @spec terminate(Reason, StateName, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _StateName, _State) ->
    defrag_server:remove_connection_worker_by_pid(self()),
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, StateName, State, Extra) ->
%%                   {ok, StateName, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, StateName, State, _Extra) ->
    {ok, StateName, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

add_modulo_32bit(Seqno, Offset) ->
    modulo32bit(Seqno+Offset).

sequence_no_in_window(SEG_SEQ, undefined, _RCV_WND, 0) ->
    true;

sequence_no_in_window(SEG_SEQ, RCV_NXT, 0, 0) ->
    modulo32bit(SEG_SEQ) == modulo32bit(RCV_NXT);

sequence_no_in_window(SEG_SEQ, RCV_NXT, RCV_WND, 0) ->
    (smaller_or_equal(RCV_NXT, SEG_SEQ) and smaller(SEG_SEQ, modulo32bit(RCV_NXT + RCV_WND)));

sequence_no_in_window(SEG_SEQ, RCV_NXT, RCV_WND, SEG_LEN) ->
    (smaller_or_equal(RCV_NXT, SEG_SEQ) and smaller(SEG_SEQ, modulo32bit(RCV_NXT + RCV_WND))) 
	or (smaller_or_equal(RCV_NXT, SEG_SEQ) and smaller((modulo32bit(SEG_SEQ + SEG_LEN +1)), modulo32bit(RCV_NXT + RCV_WND))).

forward_sequence_no(SeqnoNew, undefined, _Window) ->
    modulo32bit(SeqnoNew);

forward_sequence_no(SeqnoNew, SeqnoOld, Window) ->
    SeqA = modulo32bit(SeqnoNew),
    SeqB = modulo32bit(SeqnoOld), 
    if 
	SeqA >= SeqB ->
	    if 
		(SeqA - SeqB) =< Window ->
		    SeqA;
		true ->
		    SeqB
	    end;		
	true ->
	    Delta = ((SeqA + 16#100000000) - SeqB),
	    if 
		Delta =< Window ->
		    SeqA;
		true ->
		    SeqB
	    end
    end.

smaller_or_equal(SeqNoA, SeqNoB) -> % note: false does not mean it is greater, it may be just outside the compare window
    CompareWindow = 16#80000000,
    SeqA = modulo32bit(SeqNoA),
    SeqB = modulo32bit(SeqNoB), 
    if 
        SeqA =< SeqB ->
	    Delta = SeqB -SeqA,
	    if 
                Delta =< CompareWindow ->
		    true;
                true ->
		    false
	    end;
        true ->
	    Delta = ((SeqB + 16#100000000) - SeqA),
	    if 
		Delta =< CompareWindow ->
		    true;
		true ->
		    false
	    end
    end.

smaller(SeqNoA, SeqNoB) ->  % note: false does not mean it is greater or equal, it may be just outside the compare window
    smaller_or_equal(modulo32bit(SeqNoA+1), SeqNoB ).


%%ack_valid(SEG_ACK, undefined, RCV_NXT) ->
%%     case smaller_or_equal(SEG_ACK, RCV_NXT) of
%%   	true ->
%%		valid_ack;
%%        false ->
%%             	invalid_ack
%%      end;

%%ack_valid(SEG_ACK, SND_UNA, RCV_NXT) ->
%%    case (modulo32bit(SND_UNA) == modulo32bit(SEG_ACK)) of 
%%         true -> 
%%		io:format("Information: repetition Ack:~p received~n",[SEG_ACK]),            
%%		repetition_ack;
%%         false ->
%%	    case (smaller(SND_UNA, SEG_ACK) and smaller_or_equal(SEG_ACK, RCV_NXT)) of
%%   		true ->
%%			valid_ack;
%%        	false ->
%%			io:format("Warning: invalid Ack: ~p for SND_UNA: ~p and RCV_NXT: ~p received~n",[SEG_ACK, SND_UNA,RCV_NXT]),
%%                	invalid_ack
%%            end
%%    end.

ack_valid(SEG_ACK, undefined, _SND_WND) ->
    valid_ack;

ack_valid(SEG_ACK, SND_UNA, SND_WND) ->
    case (modulo32bit(SND_UNA) == modulo32bit(SEG_ACK)) of 
	true -> 
	    io:format("Information: repetition Ack:~p received~n",[SEG_ACK]),            
	    repetition_ack;
	false ->
	    case (smaller(SND_UNA, SEG_ACK) and smaller_or_equal(SEG_ACK, SND_UNA+SND_WND)) of
   		true ->
		    valid_ack;
        	false ->
		    io:format("Warning: invalid Ack: ~p for SND_UNA: ~p and SND_UNA+SND_WND: ~p received~n",[SEG_ACK, SND_UNA, SND_UNA+SND_WND]),
		    invalid_ack
            end
    end.


test_ack_valid(initiator, State, SEG_ACK) ->
    ack_valid(SEG_ACK, State#state.initiator_SND_UNA, 16#FFFF); %State#state.initiator_RCV_WND);%% used as send Window

test_ack_valid(responder, State, SEG_ACK) ->
    ack_valid(SEG_ACK, State#state.responder_SND_UNA, 16#FFFF); %State#state.responder_RCV_WND);%% used as send Window

test_ack_valid(close_initiator, State, SEG_ACK) ->
    ack_valid(SEG_ACK, State#state.close_initiator_SND_UNA, 16#FFFF); %State#state.close_initiator_RCV_WND);%% used as send Window

test_ack_valid(close_responder, State, SEG_ACK) ->
    ack_valid(SEG_ACK, State#state.close_responder_SND_UNA, 16#FFFF). %State#state.close_initiator_RCV_WND).%% used as send Window


test_sequence_no_in_window(initiator, State, SEG_SEQ) ->
    sequence_no_in_window(SEG_SEQ, State#state.initiator_RCV_NXT, State#state.initiator_RCV_WND, 0);

test_sequence_no_in_window(responder, State, SEG_SEQ) ->
    sequence_no_in_window(SEG_SEQ, State#state.responder_RCV_NXT, State#state.responder_RCV_WND, 0);

test_sequence_no_in_window(close_initiator, State, SEG_SEQ) ->
    sequence_no_in_window(SEG_SEQ, State#state.close_initiator_RCV_NXT, State#state.close_initiator_RCV_WND, 0);

test_sequence_no_in_window(close_responder, State, SEG_SEQ) ->
    sequence_no_in_window(SEG_SEQ, State#state.close_responder_RCV_NXT, State#state.close_responder_RCV_WND, 0).


test_sequence_no_in_window(initiator, State, SEG_SEQ, SEG_LEN) ->
    sequence_no_in_window(SEG_SEQ, State#state.initiator_RCV_NXT, State#state.initiator_RCV_WND, SEG_LEN);

test_sequence_no_in_window(responder, State, SEG_SEQ, SEG_LEN) ->
    sequence_no_in_window(SEG_SEQ, State#state.responder_RCV_NXT, State#state.responder_RCV_WND, SEG_LEN).


storeState_RCV_NXT(initiator,     State,  SEG_SEQ_plus_1) ->
    State#state{initiator_RCV_NXT = forward_sequence_no(modulo32bit(SEG_SEQ_plus_1), State#state.initiator_RCV_NXT, State#state.responder_RCV_WND)}; 

storeState_RCV_NXT(responder,     State,  SEG_SEQ_plus_1) ->
    State#state{responder_RCV_NXT = forward_sequence_no(modulo32bit(SEG_SEQ_plus_1), State#state.responder_RCV_NXT, State#state.initiator_RCV_WND)};

storeState_RCV_NXT(close_initiator,     State,  SEG_SEQ_plus_1) ->
    State#state{close_initiator_RCV_NXT = forward_sequence_no(modulo32bit(SEG_SEQ_plus_1), State#state.close_initiator_RCV_NXT, State#state.close_responder_RCV_WND)}; 

storeState_RCV_NXT(close_responder,     State,  SEG_SEQ_plus_1) ->
    State#state{close_responder_RCV_NXT = forward_sequence_no(modulo32bit(SEG_SEQ_plus_1), State#state.close_responder_RCV_NXT, State#state.close_initiator_RCV_WND)}.


storeState_RCV_NXT(initiator,     State,  SEG_SEQ_plus_1, SEG_LEN) ->
    State#state{initiator_RCV_NXT = forward_sequence_no(modulo32bit(SEG_SEQ_plus_1+SEG_LEN), State#state.initiator_RCV_NXT, State#state.responder_RCV_WND)}; 

storeState_RCV_NXT(responder,     State,  SEG_SEQ_plus_1, SEG_LEN) ->
    State#state{responder_RCV_NXT = forward_sequence_no(modulo32bit(SEG_SEQ_plus_1+SEG_LEN), State#state.responder_RCV_NXT, State#state.initiator_RCV_WND)}.


storeState_SND_UNA(_, State, _SEG_ACK, false) ->
    State;

storeState_SND_UNA(initiator, State, SEG_ACK, true) ->
    case test_ack_valid(initiator, State, SEG_ACK) of
	valid_ack ->
	    State#state{initiator_SND_UNA = add_modulo_32bit(SEG_ACK,0)};
	repetition_ack ->
	    State;
	invalid_ack ->

	    State
    end;

storeState_SND_UNA(responder, State, SEG_ACK, true) ->
    case test_ack_valid(responder, State, SEG_ACK) of
	valid_ack ->
	    State#state{responder_SND_UNA = add_modulo_32bit(SEG_ACK,0)};
	repetition_ack ->
	    State;
	invalid_ack ->
	    State
    end;

storeState_SND_UNA(close_initiator, State, SEG_ACK, true) ->
    case test_ack_valid(close_initiator, State, SEG_ACK) of
	valid_ack ->
	    State#state{close_initiator_SND_UNA = add_modulo_32bit(SEG_ACK,0)};
	repetition_ack ->
	    State;
	invalid_ack ->
	    State
    end;

storeState_SND_UNA(close_responder, State, SEG_ACK, true) ->
    case test_ack_valid(close_responder, State, SEG_ACK) of
	valid_ack ->
	    State#state{close_responder_SND_UNA = add_modulo_32bit(SEG_ACK,0)};
	repetition_ack ->
	    State;
	invalid_ack ->
	    State
    end.
storeState_SND_UNA(initiator, State, _SEG_ACK, _Payload_length, false) ->
    State;

storeState_SND_UNA(initiator, State, SEG_ACK, Payload_length, true) ->
    case test_ack_valid(initiator, State, SEG_ACK) of
	valid_ack ->
	    State#state{initiator_SND_UNA = add_modulo_32bit(SEG_ACK, Payload_length)};
	repetition_ack ->
	    State;
	invalid_ack ->
	    State
    end;

storeState_SND_UNA(responder, State, SEG_ACK, Payload_length, true) ->
    case test_ack_valid(responder, State, SEG_ACK) of
	valid_ack ->
	    State#state{responder_SND_UNA = add_modulo_32bit(SEG_ACK, Payload_length)};
	repetition_ack ->
	    State;
	invalid_ack ->
	    State
    end.


storeState_SND_WND(initiator, State, SEG_WND) ->		
    State#state{initiator_RCV_WND = SEG_WND};

storeState_SND_WND(responder, State, SEG_WND) ->		
    State#state{responder_RCV_WND = SEG_WND};

storeState_SND_WND(close_initiator, State, SEG_WND) ->		
    State#state{close_initiator_RCV_WND = SEG_WND};

storeState_SND_WND(close_responder, State, SEG_WND) ->		
    State#state{close_responder_RCV_WND = SEG_WND}.

storeState_Payload(initiator, State, SEG_SEQ, PayloadLength, Payload) ->
    State#state{initiator_payload_store = [{SEG_SEQ, PayloadLength, Payload}|State#state.initiator_payload_store]};

storeState_Payload(responder, State, SEG_SEQ, PayloadLength, Payload) ->
    State#state{responder_payload_store = [{SEG_SEQ, PayloadLength, Payload}|State#state.responder_payload_store]}.

copy_state_to_close_initiator_close_responder(initiator, State) -> 
    State#state{
      close_initiator_address = State#state.initiator_address,	
      close_initiator_port =    State#state.initiator_port,
      close_initiator_RCV_WND = State#state.initiator_RCV_WND,
      close_initiator_SND_UNA = State#state.initiator_SND_UNA,
      close_initiator_RCV_NXT = State#state.initiator_RCV_NXT,
      close_responder_address = State#state.responder_address,
      close_responder_port    = State#state.responder_port,          
      close_responder_RCV_WND = State#state.responder_RCV_WND,
      close_responder_SND_UNA = State#state.responder_SND_UNA,
      close_responder_RCV_NXT = State#state.responder_RCV_NXT};

copy_state_to_close_initiator_close_responder(responder, State) -> 
    State#state{
      close_initiator_address = State#state.responder_address,	
      close_initiator_port    = State#state.responder_port,
      close_initiator_RCV_WND = State#state.responder_RCV_WND,
      close_initiator_SND_UNA = State#state.responder_SND_UNA,
      close_initiator_RCV_NXT = State#state.responder_RCV_NXT,
      close_responder_address = State#state.initiator_address,
      close_responder_port    = State#state.initiator_port, 
      close_responder_RCV_WND = State#state.initiator_RCV_WND,
      close_responder_SND_UNA = State#state.initiator_SND_UNA, 
      close_responder_RCV_NXT = State#state.initiator_RCV_NXT}.

log_initiator_responder(StateName, SEG_SEQ, SEG_ACK, SEG_WND, State) ->
    io:format("State: ~p, SEG_SEQ: ~w, SEG_ACK: ~w, SEG_WND: ~w~n", [StateName, SEG_SEQ, SEG_ACK, SEG_WND]),
    io:format("i_address: ~p, i_port : ~w, i_RCV_WND ~w, i_SND_UNA: ~w, i_RCV_NXT:~w~n", [State#state.initiator_address, State#state.initiator_port, State#state.initiator_RCV_WND, State#state.initiator_SND_UNA, State#state.initiator_RCV_NXT]),
    io:format("r_address: ~p, r_port : ~w, r_RCV_WND ~w, r_SND_UNA: ~w, r_RCV_NXT: ~w~n", [State#state.responder_address, State#state.responder_port, State#state.responder_RCV_WND, 	State#state.responder_SND_UNA, State#state.responder_RCV_NXT]),
    true.


log_close_initiator_close_responder(StateName, SEG_SEQ, SEG_ACK, SEG_WND, State) ->
    %%	io:format("State: ~p, SEG_SEQ: ~w, SEG_ACK: ~w, SEG_WND: ~w~n", [StateName, SEG_SEQ, SEG_ACK, SEG_WND]),
    %%        io:format("ci_address: ~p, ci_port : ~w, ci_RCV_WND ~w, ci_SND_UNA: ~w, ci_RCV_NXT:~w~n", [State#state.close_initiator_address, State#state.close_initiator_port, State#state.close_initiator_RCV_WND, State#state.close_initiator_SND_UNA, State#state.close_initiator_RCV_NXT]),
    %%        io:format("cr_address: ~p, cr_port : ~w, cr_RCV_WND ~w, cr_SND_UNA: ~w, cr_RCV_NXT: ~w~n", [State#state.close_responder_address, State#state.close_responder_port, State#state.close_responder_RCV_WND, 	State#state.close_responder_SND_UNA, State#state.close_responder_RCV_NXT]),
    true.

modulo32bit(Value) ->
    Value rem 16#100000000.



