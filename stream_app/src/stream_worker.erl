

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
-module(stream_worker).

-behaviour(gen_fsm).

%% API
-export([start_link/3, forward_sequence_no/3, modulo32bit/1, send_packet/2, stop/1, smaller/2, smaller_or_equal/2]).

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
-define(MaxNumberOfSynSegSeqOnStack, 10).


%%-define(DEBUG_WORKER, true).

-ifdef(DEBUG_WORKER).
%%-define(GEN_FSM_OPTS, {debug, [trace, {log_to_file, "log/stream/trace_"++Name_s++".log"}]}).
-define(GEN_FSM_OPTS, {debug, [{log_to_file, "log/stream/trace_"++Name_s++".log"}]}).
%%-define(GEN_FSM_OPTS, {debug, [{install,{Dbg_fun,state}}]}).
%%-define(GEN_FSM_OPTS, {debug, [{install,{Dbg_fun,state}}, {log_to_file, "log/stream/trace_"++Name_s++".log"}]}).
%%-define(GEN_FSM_OPTS, {debug, [trace]}).
-else.
-define(GEN_FSM_OPTS, []).
-endif.

%%-define(DEBUG_BUFFER, true).
-ifdef(DEBUG_BUFFER).
-define(DebugBuffer(List), List).
-else.
-define(DebugBuffer(List), []).
-endif.

-define(current_function_name(),
	element(2, element(2, process_info(self(), current_function)))).

-record(state, {
	  sent_packets::integer(),
	  sent_bytes::integer(),
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
          initiator_RCV_WND_SCALE::integer(),
          responder_address::[tuple],
          responder_port::[tuple],
          responder_RCV_NXT::integer(),
	  responder_SND_UNA::integer(),
          responder_RCV_WND::integer(),
          responder_RCV_WND_SCALE::integer(),
	  close_initiator_address::string(),
	  close_initiator_port::string(),
	  close_responder_address::string(),
	  close_responder_port::string(),
          initiator_payload_store::[tuple()],  % receive window
          responder_payload_store::[tuple()],  % receive window
          initiator_ack_payload_store::binary(),
          responder_ack_payload_store::binary(),
          initiator_sack_permitted::binary(),
	  responder_sack_permitted::binary(),
          stack_trace_path::[atom()],
          initiator_syn_seg_seq_stack::[integer()] %% stack!!!
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
start_link(Instance, {packet_with_addressing, {Ack, Syn, Fin, Rst, SEG_SEQ, SEG_ACK, SEG_WND, OPT},
            	      AddressTuple, _DLT, Time, Len, Packet, PayloadLength=0}, ChildWorkerList)->
    {{Initiator_address, Initiator_port},{Responder_address, Responder_port}} = AddressTuple,
    Instance_s = integer_to_list(Instance),
    Ref_s = erlang:ref_to_list(make_ref()),
    Name_s = ?MODULE_STRING ++ "_" ++ Instance_s ++ "_" ++ Ref_s ++ "_" ++ lists:flatten(io_lib:format("~p",[now()])) ++ "_" ++
	lists:flatten(io_lib:format("~p", [Initiator_address])) ++ ":" ++
	lists:flatten(io_lib:format("~p", [Initiator_port])) ++ "_" ++
	lists:flatten(io_lib:format("~p", [Responder_address])) ++ ":" ++
	lists:flatten(io_lib:format("~p", [Responder_port])),
    Name = list_to_atom (Name_s),
    %%error_logger:info_msg("gen_server:start_link(~p)~n",[[{local, Name},?MODULE,[],[],self()]]),
    %%Dbg_fun = fun(FuncState, Event, ProcState) -> %%error_logger:warning_msg("~nDebugFun:~n-FuncState:~p~n-Event:~p~n-ProcState:~p~n", [FuncState, Event, ProcState]) end,
    gen_fsm:start_link({local,Name},?MODULE,[Instance, {packet_with_addressing, {Ack, Syn, Fin, Rst, SEG_SEQ, SEG_ACK, SEG_WND, OPT},
							AddressTuple, _DLT, Time, Len, Packet, PayloadLength=0}, ChildWorkerList],[?GEN_FSM_OPTS]).

stop(WorkerPid) ->
    gen_server:call(WorkerPid, stop_worker).

send_packet(WorkerPid, Message) ->
    ok = gen_fsm:send_event(WorkerPid, Message).


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

init([Instance,{packet_with_addressing, {Ack = false, _Syn = true, _Fin = false, _Rst = false, SEG_SEQ, SEG_ACK, SEG_WND, OPT},
		AddressTuple,
		_DLT, _Time, _Len, _Packet, _PayloadLength=0}, ChildWorkerList]) ->
    {{Initiator_address, Initiator_port},{Responder_address, Responder_port}} = AddressTuple,
    State = #state{
               sent_packets =0,
               sent_bytes = 0,
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
               responder_payload_store = [],
               initiator_ack_payload_store = <<>>,
               responder_ack_payload_store = <<>>,
               initiator_sack_permitted=undefined,
               responder_sack_permitted=undefined,
               initiator_syn_seg_seq_stack=stack_new(?MaxNumberOfSynSegSeqOnStack)
	      },
    Direction=true,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, Ack, _Syn, _Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, lists:keyfind(window_scale, 1, OPT)}|State#state.stack_trace_path])},
    StateNew1 = storeState_SND_UNA(Direction, StateNew0, SEG_ACK, Ack),
    StateNew2 = storeState_SND_WND(Direction, StateNew1, SEG_WND),
    case lists:keyfind(window_scale, 1, OPT) of
	{window_scale, ShiftCount} ->
	    StateNew3  = storeState_SND_WND_SCALE(Direction, StateNew2, ShiftCount);
	false ->
	    StateNew3  = StateNew2 % initiator_RCV_WND_SCALE remains undefined
    end,
    case lists:keyfind(sack_permitted, 1, OPT) of
	{sack_permitted, true} ->
            StateNew4  = storeState_SACK_PERMITTED(Direction, StateNew3);
	false ->
            StateNew4  = StateNew3 % initiator_sack_permitted remains undefined
    end,
    StateNew = StateNew4#state{initiator_syn_seg_seq_stack = stack_element(SEG_SEQ, StateNew4#state.initiator_syn_seg_seq_stack)},
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
%%		{Ack, Syn, Fin, Rst, SEG_SEQ, SEG_ACK, SEG_WND, OPT},
%%		{{Source_address, Source_port},{Destination_address, Destination_port}},
%%		_DLT, Time, Len, Packet, PayloadLength=0}),
state_listen( % this state ocurrs only after reset
  {packet_with_addressing,
   {Ack = false, _Syn = true, _Fin = false, _Rst = false, SEG_SEQ, SEG_ACK, SEG_WND, OPT}, % Syn after Rst
   {{Initiator_address, Initiator_port}, {Responder_address, Responder_port}},
   _DLT, _Time, _Len, _Packet, _PayloadLength=0}, State) when
      State#state.responder_address == Responder_address,
      State#state.responder_port == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port == Initiator_port ->
    %% Rst should be ignored // RFC 793, p65
    Direction=true,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, Ack, _Syn, _Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, lists:keyfind(window_scale, 1, OPT)}|State#state.stack_trace_path])},
    StateNew1 = storeState_SND_UNA(Direction, StateNew0, SEG_ACK, Ack),
    StateNew2 = storeState_SND_WND(Direction, StateNew1, SEG_WND),
    case lists:keyfind(window_scale, 1, OPT) of
	{window_scale, ShiftCount} ->
	    StateNew3  = storeState_SND_WND_SCALE(Direction, StateNew2, ShiftCount);
	false ->
	    StateNew3  = StateNew2 % initiator_RCV_WND_SCALE remains undefined
    end,
    case lists:keyfind(sack_permitted, 1, OPT) of
	{sack_permitted, true} ->
	    StateNew4  = storeState_SACK_PERMITTED(Direction,StateNew3);
	false ->
	    StateNew4  = StateNew3 % initiator_sack_permitted remains undefined
    end,
    StateNew = StateNew4#state{initiator_syn_seg_seq_stack = stack_element(SEG_SEQ, stack_new(?MaxNumberOfSynSegSeqOnStack))}, % clear stack due to reset!!
    NextStateName = state_syn_sent,
    {next_state, NextStateName, StateNew};

state_listen(
  {packet_with_addressing,
   {_Ack, _Syn, _Fin, _Rst = true, SEG_SEQ, SEG_ACK, SEG_WND, OPT}, % Rst in state_listen, see RFC 793, p. 37
   {{Responder_address, Responder_port}, {Initiator_address, Initiator_port}},
   _DLT, _Time, _Len, _Packet, _PayloadLength=0}, State) when
      State#state.responder_address == Responder_address,
      State#state.responder_port == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port == Initiator_port ->
    %% Rst should be ignored // RFC 793, p65
    Direction=false,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, _Ack, _Syn, _Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, lists:keyfind(window_scale, 1, OPT)}|State#state.stack_trace_path])},
    StateNew = StateNew0#state{initiator_syn_seg_seq_stack = stack_element(SEG_SEQ, stack_new(?MaxNumberOfSynSegSeqOnStack))}, % clear stack due to reset!!
    NextStateName = state_listen,
    {next_state, NextStateName, StateNew};

state_listen(
  {packet_with_addressing,
   {_Ack= true, _Syn, _Fin, _Rst = false, _SEG_SEQ, _SEG_ACK, _SEG_WND, _OPT}, % Ack
   {{_, _},{_,_}},
   _DLT, _Time, _Len, _Packet, _PayloadLength}, State) ->
    _Direction = any,
    StateNew = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), _Direction, _Ack, _Syn, _Fin, _Rst, _SEG_SEQ, _SEG_ACK, _SEG_WND, _PayloadLength}|State#state.stack_trace_path])},
    %% ignore all Ack packages // RCF 793 p. 65
    {next_state, state_listen, StateNew};

state_listen(timeout, State) ->
    %%error_logger:warning_msg("Closing Instance: ~p~n in state listen", [State#state.instance]),
    {stop, shutdown, State}.

state_syn_sent(
  {packet_with_addressing,
   {Ack = false, Syn = true, Fin = false, _Rst = false, SEG_SEQ, SEG_ACK, SEG_WND, OPT}, % Syn (when Ack received before)
   {{Responder_address, Responder_port}, {Initiator_address, Initiator_port}},
   _DLT, _Time, _Len, _Packet, _PayloadLength=0}, State) when
      State#state.syn_ack_received == true, % !!!!!!!! Ack received before
      State#state.responder_address == Responder_address,
      State#state.responder_port == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port == Initiator_port ->
    Direction=false,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, Ack, Syn, Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, lists:keyfind(window_scale, 1, OPT)}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ) of
	true ->
	    StateNew1 = storeState_RCV_NXT(Direction, StateNew0, SEG_SEQ, Syn or Fin),
	    StateNew2 = storeState_SND_UNA(Direction, StateNew1, SEG_ACK, Ack),
	    StateNew3 = storeState_SND_WND(Direction, StateNew2, SEG_WND),
            case lists:keyfind(window_scale, 1, OPT) of
		{window_scale, ShiftCount} ->
                    StateNew4  = storeState_SND_WND_SCALE(Direction, StateNew3, ShiftCount);
                false ->
                    StateNew4  = StateNew3 % responder_RCV_WND_SCALE remains undefined
            end,
            case lists:keyfind(sack_permitted, 1, OPT) of
		{sack_permitted, true} ->
                    StateNew  = storeState_SACK_PERMITTED(Direction, StateNew4);
                false ->
                    StateNew  = StateNew4 % responder_sack_permitted remains undefined
            end,
	    NextStateName = state_syn_sent;
	false ->
	    StateNew = State,
	    NextStateName = state_syn_sent
    end,
    {next_state, NextStateName, StateNew};

state_syn_sent(
  {packet_with_addressing,
   {Ack = true, Syn = false, Fin = false, _Rst = false, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Ack
   {{Responder_address, Responder_port}, {Initiator_address, Initiator_port}},
   _DLT, _Time, _Len, _Packet, _PayloadLength=0}, State) when
      State#state.responder_address == Responder_address,
      State#state.responder_port == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port == Initiator_port ->
    Direction=false,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, Ack, Syn, Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, _PayloadLength}|State#state.stack_trace_path])},
    case stack_member(add_modulo_32bit(SEG_ACK, -1), StateNew0#state.initiator_syn_seg_seq_stack) of
	true ->
	    StateNew1 = storeState_RCV_NXT(not(Direction), StateNew0, add_modulo_32bit(SEG_ACK, -1), _Syn = true), % initialize initiator
            StateNew2 = StateNew1#state{syn_ack_received = true},     % set flag for received Ack
	    StateNew3 = storeState_RCV_NXT(Direction, StateNew2, SEG_SEQ, Syn or Fin), % as pure ACK received, sequence number is not increased
	    StateNew4 = storeState_SND_UNA(Direction, StateNew3, SEG_ACK, Ack),
	    StateNew  = storeState_SND_WND(Direction, StateNew4, SEG_WND),
	    NextStateName = state_syn_sent;
	false ->
	    StateNew = State,
	    NextStateName = state_syn_sent
    end,
    {next_state, NextStateName, StateNew};

state_syn_sent(
  {packet_with_addressing,
   {Ack = false, _Syn = true, _Fin = false, _Rst = false, SEG_SEQ, SEG_ACK, SEG_WND, OPT}, % Syn retransmission or new Syn
   {{Initiator_address, Initiator_port}, {Responder_address, Responder_port}},
   _DLT, _Time, _Len, _Packet, _PayloadLength=0}, State) when
      State#state.responder_address == Responder_address,
      State#state.responder_port == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port == Initiator_port ->
    Direction=true,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, Ack, _Syn, _Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, lists:keyfind(window_scale, 1, OPT)}|State#state.stack_trace_path])},
    StateNew1 = storeState_SND_UNA(Direction, StateNew0, SEG_ACK, Ack),
    StateNew2 = storeState_SND_WND(Direction, StateNew1, SEG_WND),
    case lists:keyfind(window_scale, 1, OPT) of
	{window_scale, ShiftCount} ->
	    StateNew3  = storeState_SND_WND_SCALE(Direction, StateNew2, ShiftCount);
        false ->
	    StateNew3  = StateNew2 % initiator_RCV_WND_SCALE remains undefined
    end,
    case lists:keyfind(sack_permitted, 1, OPT) of
	{sack_permitted, true} ->
	    StateNew4  = storeState_SACK_PERMITTED(Direction, StateNew3);
        false ->
	    StateNew4  = StateNew3 % initiator_sack_permitted remains undefined
    end,
    StateNew = StateNew4#state{initiator_syn_seg_seq_stack = stack_element(SEG_SEQ, StateNew4#state.initiator_syn_seg_seq_stack)},
    NextStateName = state_syn_sent,
    {next_state, NextStateName, StateNew};

state_syn_sent(
  {packet_with_addressing,
   {Ack = true, Syn = true, Fin = false, _Rst = false, SEG_SEQ, SEG_ACK, SEG_WND, OPT}, % Syn-Ack
   {{Responder_address, Responder_port}, {Initiator_address, Initiator_port}},
   _DLT, _Time, _Len, _Packet, _PayloadLength=0}, State) when
      State#state.responder_address == Responder_address,
      State#state.responder_port == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port == Initiator_port ->
    Direction=false,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, Ack, Syn, Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, lists:keyfind(window_scale, 1, OPT)}|State#state.stack_trace_path])},
    case stack_member(add_modulo_32bit(SEG_ACK, -1), StateNew0#state.initiator_syn_seg_seq_stack) of
	true ->
            StateNew1 = storeState_RCV_NXT(not(Direction), StateNew0, add_modulo_32bit(SEG_ACK, -1), _Syn = true), % initialize initiator
	    StateNew2 = storeState_RCV_NXT(Direction, StateNew1, SEG_SEQ, Syn or Fin),
	    StateNew3 = storeState_SND_UNA(Direction, StateNew2, SEG_ACK, Ack),
	    StateNew4 = storeState_SND_WND(Direction, StateNew3, SEG_WND),
            case lists:keyfind(window_scale, 1, OPT) of
		{window_scale, ShiftCount} ->
                    StateNew5  = storeState_SND_WND_SCALE(Direction, StateNew4, ShiftCount);
                false ->
                    StateNew5  = StateNew4 % responder_RCV_WND_SCALE remains undefined
            end,
            case lists:keyfind(sack_permitted, 1, OPT) of
		{sack_permitted, true} ->
                    StateNew  = storeState_SACK_PERMITTED(Direction, StateNew5);
                false ->
                    StateNew  = StateNew5 % responder_sack_permitted remains undefined
            end,
	    NextStateName = state_syn_syn_ack_sent;
	false ->
	    StateNew = State,
	    NextStateName = state_syn_sent
    end,
    {next_state, NextStateName, StateNew};

state_syn_sent(
  {packet_with_addressing,
   {Ack, Syn = false, Fin = true, _Rst = false, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Fin / Fin-Ack
   {{Initiator_address, Initiator_port}, {Responder_address, Responder_port}},
   _DLT, _Time, _Len, _Packet, _PayloadLength=0}, State) when
      State#state.responder_address == Responder_address,
      State#state.responder_port == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port == Initiator_port ->
    Direction=true,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, Ack, Syn, Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, _PayloadLength}|State#state.stack_trace_path])},
    Close_Direction = true,
    StateNew1 = copy_state_to_close_initiator_close_responder(Direction, StateNew0),
    StateNew2 = storeState_RCV_NXT(Close_Direction, StateNew1, SEG_SEQ, Syn or Fin),
    StateNew3 = storeState_SND_UNA(Close_Direction, StateNew2, SEG_ACK, Ack),
    StateNew  = storeState_SND_WND(Close_Direction, StateNew3, SEG_WND),
    NextStateName = state_fin_wait_1,
    {next_state, NextStateName, StateNew};

state_syn_sent(
  {packet_with_addressing,
   {_Ack, _Syn, _Fin, _Rst = true, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Rst
   {{Initiator_address, Initiator_port},
    {Responder_address, Responder_port}},
   _DLT, _Time, _Len, _Packet, PayloadLength}, State) when
      State#state.responder_address == Responder_address,
      State#state.responder_port    == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port    == Initiator_port ->
    Direction=true,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, _Ack, _Syn, _Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ, PayloadLength) of
	true ->
            StateNew = StateNew0,
	    NextStateName = state_listen;
        false ->
	    %%error_logger:warning_msg("Warning!!!!Direction:~w, SEG_SEQ: ~w, PayloadLength ~w, RCV_NXT: ~w, RCV_WND: ~w~n", [Direction, SEG_SEQ, PayloadLength, State#state.responder_RCV_NXT, calculate_window(Direction, State)]),
            StateNew = StateNew0,
            NextStateName = state_syn_sent,
            log_initiator_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew)
    end,
    {next_state, NextStateName, StateNew, 10000};

state_syn_sent(
  {packet_with_addressing,
   {_Ack, _Syn, _Fin, _Rst = true, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Rst
   {{Responder_address, Responder_port},
    {Initiator_address, Initiator_port}},
   _DLT, _Time, _Len, _Packet, PayloadLength}, State) when
      State#state.responder_address == Responder_address,
      State#state.responder_port    == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port    == Initiator_port ->
    Direction=false,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, _Ack, _Syn, _Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ, PayloadLength) of
	true ->
            StateNew = StateNew0,
	    NextStateName = state_listen;
        false ->
	    %%error_logger:warning_msg("Warning!!!!Direction:~w, SEG_SEQ: ~w, PayloadLength ~w, RCV_NXT: ~w, RCV_WND: ~w~n", [Direction, SEG_SEQ, PayloadLength, State#state.responder_RCV_NXT, calculate_window(Direction, State)]),
            StateNew = StateNew0,
            NextStateName = state_syn_sent,
            log_initiator_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew)
    end,
    {next_state, NextStateName, StateNew, 10000}.

state_syn_syn_ack_sent(
  {packet_with_addressing,
   {Ack = true, Syn = false, Fin = false, _Rst = false, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Ack
   {{Initiator_address, Initiator_port}, {Responder_address, Responder_port}},
   _DLT, _Time, _Len, _Packet, _PayloadLength=0}, State) when
      State#state.responder_address == Responder_address,
      State#state.responder_port == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port == Initiator_port ->
    Direction=true,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, Ack, Syn, Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, _PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ) of
	true ->
	    StateNew1 = storeState_RCV_NXT(Direction, StateNew0,     SEG_SEQ, Syn or Fin), % as pure ACK received, sequence number is not increased
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
   {Ack = true, Syn = false, Fin = false, _Rst = false, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Ack retransmission
   {{Responder_address, Responder_port}, {Initiator_address, Initiator_port}},
   _DLT, _Time, _Len, _Packet, _PayloadLength=0}, State) when
      State#state.responder_address == Responder_address,
      State#state.responder_port == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port == Initiator_port ->
    Direction=false,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, Ack, Syn, Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, _PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ) of
	true ->
	    StateNew1 = storeState_RCV_NXT(Direction, StateNew0,     SEG_SEQ, Syn or Fin),% as pure ACK received, sequence number is not increased
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
   {Ack, Syn = false, Fin = true, _Rst = false, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Fin / Fin-Ack
   {{Initiator_address, Initiator_port}, {Responder_address, Responder_port}},
   _DLT, _Time, _Len, _Packet, _PayloadLength=0}, State) when
      State#state.responder_address == Responder_address,
      State#state.responder_port == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port == Initiator_port ->
    Direction=true,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, Ack, Syn, Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, _PayloadLength}|State#state.stack_trace_path])},
    Close_Direction = close_initiator,
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ) of
	true ->
            StateNew1 = copy_state_to_close_initiator_close_responder(Direction, StateNew0),
    	    StateNew2 = storeState_RCV_NXT(Close_Direction, StateNew1, SEG_SEQ, Syn or Fin),
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
   {Ack, Syn = false, Fin = true, _Rst = false, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Fin / Fin-Ack
   {{Responder_address, Responder_port}, {Initiator_address, Initiator_port}},
   _DLT, _Time, _Len, _Packet, _PayloadLength=0}, State) when
      State#state.responder_address == Responder_address,
      State#state.responder_port == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port == Initiator_port ->
    Direction=false,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, Ack, Syn, Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, _PayloadLength}|State#state.stack_trace_path])},
    Close_Direction = close_initiator,
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ) of
	true ->
            StateNew1 = copy_state_to_close_initiator_close_responder(Direction, StateNew0),
    	    StateNew2 = storeState_RCV_NXT(Close_Direction, StateNew1, SEG_SEQ, Syn or Fin),
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
   {_Ack, _Syn, _Fin, _Rst = true, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Rst
   {{Initiator_address, Initiator_port},
    {Responder_address, Responder_port}},
   _DLT, _Time, _Len, _Packet, PayloadLength}, State) when
      State#state.responder_address == Responder_address,
      State#state.responder_port    == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port    == Initiator_port ->
    Direction=true,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, _Ack, _Syn, _Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ, PayloadLength) of
	true ->
            StateNew = StateNew0,
	    NextStateName = state_listen;
        false ->
	    %%error_logger:warning_msg("Warning!!!!Direction:~w, SEG_SEQ: ~w, PayloadLength ~w, RCV_NXT: ~w, RCV_WND: ~w~n", [Direction, SEG_SEQ, PayloadLength, State#state.responder_RCV_NXT, calculate_window(Direction, State)]),
            StateNew = StateNew0,
            NextStateName = state_syn_syn_ack_sent,
            log_initiator_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew)
    end,
    {next_state, NextStateName, StateNew, 10000};

state_syn_syn_ack_sent(
  {packet_with_addressing,
   {_Ack, _Syn, _Fin, _Rst = true, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Rst
   {{Responder_address, Responder_port},
    {Initiator_address, Initiator_port}},
   _DLT, _Time, _Len, _Packet, PayloadLength}, State) when
      State#state.responder_address == Responder_address,
      State#state.responder_port    == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port    == Initiator_port ->
    Direction=false,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, _Ack, _Syn, _Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ, PayloadLength) of
	true ->
            StateNew = StateNew0,
	    NextStateName = state_listen;
        false ->
	    %%error_logger:warning_msg("Warning!!!!Direction:~w, SEG_SEQ: ~w, PayloadLength ~w, RCV_NXT: ~w, RCV_WND: ~w~n", [Direction, SEG_SEQ, PayloadLength, State#state.responder_RCV_NXT, calculate_window(Direction, State)]),
            StateNew = StateNew0,
            NextStateName = state_syn_syn_ack_sent,
            log_initiator_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew)
    end,
    {next_state, NextStateName, StateNew, 10000}.

state_syn_received(
  {packet_with_addressing,
   {Ack = true, Syn = false, Fin = false, _Rst = false, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Ack
   {{Initiator_address, Initiator_port}, {Responder_address, Responder_port}},
   _DLT, _Time, _Len, _Packet, _PayloadLength=0}, State) when
      State#state.responder_address == Responder_address,
      State#state.responder_port == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port == Initiator_port ->
    Direction=true,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, Ack, Syn, Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, _PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ) of
	true ->
	    StateNew1 = storeState_RCV_NXT(Direction, StateNew0,     SEG_SEQ, Syn or Fin),% as pure ACK received, sequence number is not increased
	    StateNew2 = storeState_SND_UNA(Direction, StateNew1, SEG_ACK, Ack),
	    StateNew  = storeState_SND_WND(Direction, StateNew2, SEG_WND),
	    NextStateName = state_established;
        false ->
            StateNew = State,
            NextStateName = state_established
    end,
    {next_state, NextStateName, StateNew};

state_syn_received(
  {packet_with_addressing,
   {Ack, Syn = false, Fin = true, _Rst = false, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Fin / Fin-Ack
   {{Initiator_address, Initiator_port}, {Responder_address, Responder_port}},
   _DLT, _Time, _Len, _Packet, _PayloadLength=0}, State) when
      State#state.responder_address == Responder_address,
      State#state.responder_port == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port == Initiator_port ->
    Direction=true,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, Ack, Syn, Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, _PayloadLength}|State#state.stack_trace_path])},
    Close_Direction = close_initiator,
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ) of
	true ->
            StateNew1 = copy_state_to_close_initiator_close_responder(Direction, StateNew0),
    	    StateNew2 = storeState_RCV_NXT(Close_Direction, StateNew1, SEG_SEQ, Syn or Fin),
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
   {Ack, Syn = false, Fin = true, _Rst = false, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Fin / Fin-Ack
   {{Responder_address, Responder_port}, {Initiator_address, Initiator_port}},
   _DLT, _Time, _Len, _Packet, _PayloadLength=0}, State) when
      State#state.responder_address == Responder_address,
      State#state.responder_port == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port == Initiator_port ->
    Direction=false,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, Ack, Syn, Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, _PayloadLength}|State#state.stack_trace_path])},
    Close_Direction = close_initiator,
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ) of
	true ->
            StateNew1 = copy_state_to_close_initiator_close_responder(Direction, StateNew0),
    	    StateNew2 = storeState_RCV_NXT(Close_Direction, StateNew1, SEG_SEQ, Syn or Fin),
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
   {_Ack, _Syn, _Fin, _Rst = true, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Rst as connection initiator received. 
   {{Initiator_address, Initiator_port},
    {Responder_address, Responder_port}},
   _DLT, _Time, _Len, _Packet, PayloadLength}, State) when
      State#state.responder_address == Responder_address,
      State#state.responder_port    == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port    == Initiator_port ->
    Direction=true,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, _Ack, _Syn, _Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ, PayloadLength) of
	true ->
            StateNew = StateNew0,
	    NextStateName = state_time_wait;
        false ->
	    %%error_logger:warning_msg("Warning!!!!Direction:~w, SEG_SEQ: ~w, PayloadLength ~w, RCV_NXT: ~w, RCV_WND: ~w~n", [Direction, SEG_SEQ, PayloadLength, State#state.responder_RCV_NXT, calculate_window(Direction, State)]),
            StateNew = StateNew0,
            NextStateName = state_syn_received,
            log_initiator_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew)
    end,
    {next_state, NextStateName, StateNew, 10000};

state_syn_received(
  {packet_with_addressing,
   {_Ack, _Syn, _Fin, _Rst = true, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Rst as connection responder received, see RFC 793, p. 37. Go back to listen.
   {{Responder_address, Responder_port},
    {Initiator_address, Initiator_port}},
   _DLT, _Time, _Len, _Packet, PayloadLength}, State) when
      State#state.responder_address == Responder_address,
      State#state.responder_port    == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port    == Initiator_port ->
    Direction=false,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, _Ack, _Syn, _Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ, PayloadLength) of
	true ->
            StateNew = StateNew0,
	    NextStateName = state_listen;
        false ->
	    %%error_logger:warning_msg("Warning!!!!Direction:~w, SEG_SEQ: ~w, PayloadLength ~w, RCV_NXT: ~w, RCV_WND: ~w~n", [Direction, SEG_SEQ, PayloadLength, State#state.responder_RCV_NXT, calculate_window(Direction, State)]),
            StateNew = StateNew0,
            NextStateName = state_syn_received,
            log_initiator_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew)
    end,
    {next_state, NextStateName, StateNew, 10000}.

state_established(
  {packet_with_addressing,
   {Ack, Syn = false, Fin = false, _Rst = false, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % payload, Note: if Ack == false, SEG_ACK should be 0
   {{Initiator_address, Initiator_port} = Source, {Responder_address, Responder_port} = Destination},
   _DLT, _Time, _Len, Packet, PayloadLength}, State) when
      State#state.responder_address == Responder_address,
      State#state.responder_port == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port == Initiator_port ->
    [_EtherIgnore, _IP, _TCP, Payload] = Packet,
    Direction=true,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, Ack, Syn, Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ, PayloadLength) of
	true ->
	    StateNew1  = storeState_Payload(Direction, StateNew0, SEG_SEQ, PayloadLength, <<Payload:PayloadLength/binary>>),
	    StateNew2  = checkPayloadReceptionBuffer(not(Direction), Ack, SEG_ACK, Syn or Fin, StateNew1),
	    StateNew3 = storeState_SND_UNA(Direction, StateNew2, SEG_ACK, Ack),
	    StateNew4  = storeState_SND_WND(Direction, StateNew3, SEG_WND),
	    StateNew   = forward_stream_ack_payload_store(Direction, Fin, Source, Destination, StateNew4);
        false ->
	    %%error_logger:warning_msg("Warning!!!!Direction:~w, SEG_SEQ: ~w, PayloadLength ~w, RCV_NXT: ~w, RCV_WND: ~w~n", [Direction, SEG_SEQ, PayloadLength, State#state.initiator_RCV_NXT, calculate_window(Direction, State)]),
	    StateNew = State
    end,
    {next_state, state_established, StateNew};

state_established(
  {packet_with_addressing,
   {Ack, Syn = false, Fin = false, _Rst = false, SEG_SEQ, SEG_ACK, SEG_WND, _OPT},  % payload, Note: if Ack == false, SEG_ACK should be 0
   {{Responder_address, Responder_port} = Source, {Initiator_address, Initiator_port} = Destination},
   _DLT, _Time, _Len, Packet, PayloadLength}, State) when
      State#state.responder_address == Responder_address,
      State#state.responder_port == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port == Initiator_port ->
    [_EtherIgnore, _IP, _TCP, Payload] = Packet,
    Direction=false,
    StateNew0 =State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, Ack, Syn, Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ, PayloadLength) of
	true ->
	    StateNew1 = storeState_Payload(Direction, StateNew0, SEG_SEQ, PayloadLength, <<Payload:PayloadLength/binary>>),
	    StateNew2  = checkPayloadReceptionBuffer(not(Direction), Ack, SEG_ACK, Syn or Fin, StateNew1),
	    StateNew3 = storeState_SND_UNA(Direction, StateNew2, SEG_ACK, Ack),
	    StateNew4  = storeState_SND_WND(Direction, StateNew3, SEG_WND),
	    StateNew   = forward_stream_ack_payload_store(Direction, Fin, Source, Destination, StateNew4);
	false ->
	    %%error_logger:warning_msg("Warning!!!!Direction:~w, SEG_SEQ: ~w, PayloadLength ~w, RCV_NXT: ~w, RCV_WND: ~w~n", [Direction, SEG_SEQ, PayloadLength, State#state.responder_RCV_NXT, calculate_window(Direction, State)]),
	    StateNew = State
    end,
    {next_state, state_established, StateNew};

state_established(
  {packet_with_addressing,
   {Ack = true, Syn = true, Fin = false, _Rst = false, SEG_SEQ, SEG_ACK, SEG_WND, _OPT},  % Syn-Ack retransmission
   {{Initiator_address, Initiator_port}, {Responder_address, Responder_port}},
   _DLT, _Time, _Len, _Packet, _PayloadLength=0}, State) when
      State#state.responder_address == Responder_address,
      State#state.responder_port == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port == Initiator_port ->
    Direction=true,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, Ack, Syn, Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, _PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ) of
	true ->
	    StateNew1 = storeState_RCV_NXT(Direction, StateNew0, SEG_SEQ, Syn or Fin),
	    StateNew2 = storeState_SND_UNA(Direction, StateNew1, SEG_ACK, Ack),
	    StateNew  = storeState_SND_WND(Direction, StateNew2, SEG_WND);
        false ->
            StateNew = State
    end,
    {next_state, state_established, StateNew};

state_established(
  {packet_with_addressing,
   {Ack = true, Syn = true, Fin = false, _Rst = false, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Syn-Ack retransmission
   {{Responder_address, Responder_port}, {Initiator_address, Initiator_port}},
   _DLT, _Time, _Len, _Packet, _PayloadLength=0}, State) when
      State#state.responder_address == Responder_address,
      State#state.responder_port == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port == Initiator_port ->
    Direction=false,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, Ack, Syn, Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, _PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ) of
	true ->
	    StateNew1 = storeState_RCV_NXT(Direction, StateNew0, SEG_SEQ, Syn or Fin),
	    StateNew2 = storeState_SND_UNA(Direction, StateNew1, SEG_ACK, Ack),
	    StateNew  = storeState_SND_WND(Direction, StateNew2, SEG_WND);
        false ->
            StateNew = State
    end,
    {next_state, state_established, StateNew};

state_established(
  {packet_with_addressing,
   {Ack = true, Syn = false, Fin = false, _Rst = false, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Ack without payload, Note: SEG_SEQ should be 0
   {{Initiator_address, Initiator_port}, {Responder_address, Responder_port}},
   _DLT, _Time, _Len, _Packet, _PayloadLength=0}, State) when
      State#state.responder_address == Responder_address,
      State#state.responder_port == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port == Initiator_port ->
    Direction=true,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, Ack, Syn, Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, _PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ) of
	true ->
	    StateNew1 = storeState_RCV_NXT(Direction, StateNew0,     SEG_SEQ, Syn or Fin), % as pure ACK received, sequence number is not increased
	    StateNew2 = storeState_SND_UNA(Direction, StateNew1, SEG_ACK, Ack),
	    StateNew  = storeState_SND_WND(Direction, StateNew2, SEG_WND);
        false ->
            StateNew = State
    end,
    {next_state, state_established, StateNew};

state_established(
  {packet_with_addressing,
   {Ack = true, Syn = false, Fin = false, _Rst = false, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Ack without payload, Note: SEG_SEQ should be 0
   {{Responder_address, Responder_port}, {Initiator_address, Initiator_port}},
   _DLT, _Time, _Len, _Packet, _PayloadLength=0}, State) when
      State#state.responder_address == Responder_address,
      State#state.responder_port == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port == Initiator_port ->
    Direction=false,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, Ack, Syn, Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, _PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ) of
	true ->
	    StateNew1 = storeState_RCV_NXT(Direction, StateNew0,     SEG_SEQ, Syn or Fin), % as pure ACK received, sequence number is not increased
	    StateNew2 = storeState_SND_UNA(Direction, StateNew1, SEG_ACK, Ack),
	    StateNew  = storeState_SND_WND(Direction, StateNew2, SEG_WND);
        false ->
            StateNew = State
    end,
    {next_state, state_established, StateNew};

state_established(
  {packet_with_addressing,
   {Ack, _Syn = false, Fin = true, _Rst = false, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Fin / Fin-Ack
   {{Initiator_address, Initiator_port} = Source, {Responder_address, Responder_port} = Destination},
   _DLT, _Time, _Len, Packet, PayloadLength}, State) when
      State#state.responder_address == Responder_address,
      State#state.responder_port == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port == Initiator_port ->
    Direction=true,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, Ack, _Syn, Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    [_EtherIgnore, _IP, _TCP, Payload] = Packet,
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ, PayloadLength) of
	true ->
            StateNew1 = copy_state_to_close_initiator_close_responder(Direction, StateNew0),
						% StateNew2 = storeState_RCV_NXT(Direction, StateNew1, SEG_SEQ, Syn or Fin),
	    StateNew2 = storeState_SND_UNA(Direction, StateNew1, SEG_ACK, Ack),
	    StateNew3 = storeState_SND_WND(Direction, StateNew2, SEG_WND),
      	    StateNew4 = storeState_Payload(Direction, StateNew3, SEG_SEQ, PayloadLength, <<Payload:PayloadLength/binary>>),
	    StateNew   = forward_stream_ack_payload_store(Direction, Fin, Source, Destination, StateNew4),
	    NextStateName = state_fin_wait_1;
        false ->
	    %%error_logger:warning_msg("Warning!!!!Direction:~w, SEG_SEQ: ~w, PayloadLength ~w, RCV_NXT: ~w, RCV_WND: ~w~n", [Direction, SEG_SEQ, PayloadLength, State#state.initiator_RCV_NXT, calculate_window(Direction, State)]),
            StateNew = State,
            NextStateName = state_established,
            log_initiator_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew)
    end,
    {next_state, NextStateName, StateNew};

state_established(
  {packet_with_addressing,
   {Ack, _Syn = false, Fin = true, _Rst = false, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Fin / Fin-Ack
   {{Responder_address, Responder_port} = Source, {Initiator_address, Initiator_port} = Destination},
   _DLT, _Time, _Len, Packet, PayloadLength}, State) when
      State#state.responder_address == Responder_address,
      State#state.responder_port == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port == Initiator_port ->
    [_EtherIgnore, _IP, _TCP, Payload] = Packet,
    Direction=false,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, Ack, _Syn, Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ, PayloadLength) of
	true ->
            StateNew1 = copy_state_to_close_initiator_close_responder(Direction, StateNew0),
						%StateNew2 = storeState_RCV_NXT(Direction, StateNew1, SEG_SEQ, Syn or Fin),
	    StateNew2 = storeState_SND_UNA(Direction, StateNew1, SEG_ACK, Ack),
	    StateNew3 = storeState_SND_WND(Direction, StateNew2, SEG_WND),
      	    StateNew4 = storeState_Payload(Direction, StateNew3, SEG_SEQ, PayloadLength, <<Payload:PayloadLength/binary>>),
	    StateNew   = forward_stream_ack_payload_store(Direction, Fin, Source, Destination, StateNew4),
	    NextStateName = state_fin_wait_1;
        false ->
            %%error_logger:warning_msg("Warning!!!!Direction:~w, SEG_SEQ: ~w, PayloadLength ~w, RCV_NXT: ~w, RCV_WND: ~w~n", [Direction, SEG_SEQ, PayloadLength, State#state.responder_RCV_NXT, calculate_window(Direction, State)]),
            StateNew = State,
            NextStateName = state_established,
            log_initiator_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew)
    end,
    {next_state, NextStateName, StateNew};

state_established(
  {packet_with_addressing,
   {_Ack, _Syn, _Fin, _Rst = true, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Rst
   {{Initiator_address, Initiator_port},
    {Responder_address, Responder_port}},
   _DLT, _Time, _Len, _Packet, PayloadLength}, State) when
      State#state.responder_address == Responder_address,
      State#state.responder_port    == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port    == Initiator_port ->
    Direction=true,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, _Ack, _Syn, _Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ, PayloadLength) of
	true ->
            StateNew = copy_state_to_close_initiator_close_responder(Direction, StateNew0),
	    NextStateName = state_time_wait;
        false ->
            %%error_logger:warning_msg("Warning!!!!Direction:~w, SEG_SEQ: ~w, PayloadLength ~w, RCV_NXT: ~w, RCV_WND: ~w~n", [Direction, SEG_SEQ, PayloadLength, State#state.responder_RCV_NXT, calculate_window(Direction, State)]),
            StateNew = StateNew0,
            NextStateName = state_established,
            log_initiator_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew)
    end,
    {next_state, NextStateName, StateNew, 10000};

state_established(
  {packet_with_addressing,
   {_Ack, _Syn, _Fin, _Rst = true, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Rst
   {{Responder_address, Responder_port},
    {Initiator_address, Initiator_port}},
   _DLT, _Time, _Len, _Packet, PayloadLength}, State) when
      State#state.responder_address == Responder_address,
      State#state.responder_port    == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port    == Initiator_port ->
    Direction=false,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, _Ack, _Syn, _Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ, PayloadLength) of
	true ->
            StateNew = copy_state_to_close_initiator_close_responder(Direction, StateNew0),
	    NextStateName = state_time_wait;
        false ->
            %%error_logger:warning_msg("Warning!!!!Direction:~w, SEG_SEQ: ~w, PayloadLength ~w, RCV_NXT: ~w, RCV_WND: ~w~n", [Direction, SEG_SEQ, PayloadLength, State#state.responder_RCV_NXT, calculate_window(Direction, State)]),
            StateNew = StateNew0,
            NextStateName = state_established,
            log_initiator_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew)
    end,
    {next_state, NextStateName, StateNew, 10000}.

state_fin_wait_1(
  {packet_with_addressing,
   {Ack = true, Syn = false, Fin = true, _Rst = false, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Fin-Ack
   {{Close_responder_address, Close_responder_port} = Source,
    {Close_initiator_address, Close_initiator_port} = Destination},
   _DLT, _Time, _Len, Packet, PayloadLength}, State) when
      State#state.close_responder_address == Close_responder_address,
      State#state.close_responder_port    == Close_responder_port,
      State#state.close_initiator_address == Close_initiator_address,
      State#state.close_initiator_port    == Close_initiator_port ->
    Direction = determine_Direction({Source, Destination} , State),
    [_EtherIgnore, _IP, _TCP, Payload] = Packet,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, Ack, Syn, Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ) of
	true ->
            StateNew1  = storeState_Payload(Direction, StateNew0, SEG_SEQ, PayloadLength, <<Payload:PayloadLength/binary>>),
	    StateNew2  = checkPayloadReceptionBuffer(not(Direction), Ack, SEG_ACK, Syn or Fin, StateNew1),
	    StateNew3 = storeState_SND_UNA(Direction, StateNew2, SEG_ACK, Ack),
	    StateNew4  = storeState_SND_WND(Direction, StateNew3, SEG_WND),
	    StateNew   = forward_stream_ack_payload_store(Direction, Fin, Source, Destination, StateNew4),
	    NextStateName = state_fin_finack_wait,
            log_initiator_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew);
        false ->
            StateNew = State,
            NextStateName = state_fin_wait_1,
            log_initiator_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew)
    end,
    {next_state, NextStateName, StateNew};

state_fin_wait_1(
  {packet_with_addressing,
   {Ack= true, Syn = false, Fin = true, _Rst = false, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Fin-Ack retransmission
   {{Close_initiator_address, Close_initiator_port} = Source,
    {Close_responder_address, Close_responder_port} = Destination},
   _DLT, _Time, _Len, Packet, PayloadLength}, State) when
      State#state.close_responder_address == Close_responder_address,
      State#state.close_responder_port    == Close_responder_port,
      State#state.close_initiator_address == Close_initiator_address,
      State#state.close_initiator_port    == Close_initiator_port ->
    Direction = determine_Direction({Source, Destination} , State),
    [_EtherIgnore, _IP, _TCP, Payload] = Packet,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, Ack, Syn, Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ) of
	true ->
            StateNew1  = storeState_Payload(Direction, StateNew0, SEG_SEQ, PayloadLength, <<Payload:PayloadLength/binary>>),
	    StateNew2  = checkPayloadReceptionBuffer(not(Direction), Ack, SEG_ACK, Syn or Fin, StateNew1),
	    StateNew3 = storeState_SND_UNA(Direction, StateNew2, SEG_ACK, Ack),
	    StateNew4  = storeState_SND_WND(Direction, StateNew3, SEG_WND),
	    StateNew   = forward_stream_ack_payload_store(Direction, Fin, Source, Destination, StateNew4),
	    NextStateName = state_fin_wait_1,
            log_initiator_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew);
	false ->
	    StateNew = State,
	    NextStateName = state_fin_wait_1,
            log_initiator_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew)
    end,
    {next_state, NextStateName, StateNew};

state_fin_wait_1(
  {packet_with_addressing,
   {Ack = true, Syn = false, Fin = false, _Rst = false, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Ack
   {{Close_responder_address, Close_responder_port} = Source,
    {Close_initiator_address, Close_initiator_port} = Destination},
   _DLT, _Time, _Len, Packet, PayloadLength}, State) when
      State#state.close_responder_address == Close_responder_address,
      State#state.close_responder_port    == Close_responder_port,
      State#state.close_initiator_address == Close_initiator_address,
      State#state.close_initiator_port    == Close_initiator_port ->
    Direction = determine_Direction({Source, Destination} , State),
    [_EtherIgnore, _IP, _TCP, Payload] = Packet,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, Ack, Syn, Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ) of
	true ->
            StateNew1  = storeState_Payload(Direction, StateNew0, SEG_SEQ, PayloadLength, <<Payload:PayloadLength/binary>>),
	    StateNew2  = checkPayloadReceptionBuffer(not(Direction), Ack, SEG_ACK, Syn or Fin, StateNew1),
	    StateNew3 = storeState_SND_UNA(Direction, StateNew2, SEG_ACK, Ack),
	    StateNew4  = storeState_SND_WND(Direction, StateNew3, SEG_WND),
	    StateNew   = forward_stream_ack_payload_store(Direction, Fin, Source, Destination, StateNew4),
	    NextStateName = state_fin_wait_2,
            log_initiator_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew);
	false ->
	    StateNew = State,
	    NextStateName = state_fin_wait_1,
            log_initiator_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew)
    end,
    {next_state, NextStateName, StateNew};

state_fin_wait_1(
  {packet_with_addressing,
   {Ack = true, Syn = false, Fin = false, _Rst = false, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % unexpected Ack
   {{Close_initiator_address, Close_initiator_port} = Source,
    {Close_responder_address, Close_responder_port} = Destination},
   _DLT, _Time, _Len, Packet, PayloadLength}, State) when
      State#state.close_responder_address == Close_responder_address,
      State#state.close_responder_port    == Close_responder_port,
      State#state.close_initiator_address == Close_initiator_address,
      State#state.close_initiator_port    == Close_initiator_port ->
    Direction = determine_Direction({Source, Destination} , State),
    [_EtherIgnore, _IP, _TCP, Payload] = Packet,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, Ack, Syn, Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ) of
	true ->
            StateNew1  = storeState_Payload(Direction, StateNew0, SEG_SEQ, PayloadLength, <<Payload:PayloadLength/binary>>),
	    StateNew2  = checkPayloadReceptionBuffer(not(Direction), Ack, SEG_ACK, Syn or Fin, StateNew1),
	    StateNew3 = storeState_SND_UNA(Direction, StateNew2, SEG_ACK, Ack),
	    StateNew4  = storeState_SND_WND(Direction, StateNew3, SEG_WND),
	    StateNew   = forward_stream_ack_payload_store(Direction, Fin, Source, Destination, StateNew4),
	    NextStateName = state_fin_wait_1,
            log_initiator_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew);
	false ->
	    StateNew = State,
	    NextStateName = state_fin_wait_1,
            log_initiator_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew)
    end,
    {next_state, NextStateName, StateNew};

state_fin_wait_1(
  {packet_with_addressing,
   {Ack=false, Syn = false, Fin = true, _Rst = false, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Fin, optional payload
   {{Close_responder_address, Close_responder_port} = Source,
    {Close_initiator_address, Close_initiator_port} = Destination},
   _DLT, _Time, _Len, Packet, PayloadLength}, State) when
      State#state.fin_ack_received == true, % when Ack for Fin has been received before
      State#state.close_responder_address == Close_responder_address,
      State#state.close_responder_port    == Close_responder_port,
      State#state.close_initiator_address == Close_initiator_address,
      State#state.close_initiator_port    == Close_initiator_port ->
    Direction = determine_Direction({Source, Destination} , State),
    [_EtherIgnore, _IP, _TCP, Payload] = Packet,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, Ack, Syn, Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ) of
	true ->
            StateNew1  = storeState_Payload(Direction, StateNew0, SEG_SEQ, PayloadLength, <<Payload:PayloadLength/binary>>),
	    StateNew2  = checkPayloadReceptionBuffer(not(Direction), Ack, SEG_ACK, Syn or Fin, StateNew1),
	    StateNew3 = storeState_SND_UNA(Direction, StateNew2, SEG_ACK, Ack),
	    StateNew4  = storeState_SND_WND(Direction, StateNew3, SEG_WND),
	    StateNew   = forward_stream_ack_payload_store(Direction, Fin, Source, Destination, StateNew4),
	    NextStateName = state_fin_fin_wait,
            log_initiator_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew);
	false ->
	    StateNew = State,
	    NextStateName = state_fin_wait_1,
            log_initiator_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew)
    end,
    {next_state, NextStateName, StateNew};

state_fin_wait_1(
  {packet_with_addressing,
   {Ack=false, Syn = false, Fin = true, _Rst = false, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Fin, optional payload
   {{Close_responder_address, Close_responder_port} = Source,
    {Close_initiator_address, Close_initiator_port} = Destination},
   _DLT, _Time, _Len, Packet, PayloadLength}, State) when
      State#state.close_responder_address == Close_responder_address,
      State#state.close_responder_port    == Close_responder_port,
      State#state.close_initiator_address == Close_initiator_address,
      State#state.close_initiator_port    == Close_initiator_port ->
    Direction = determine_Direction({Source, Destination} , State),
    [_EtherIgnore, _IP, _TCP, Payload] = Packet,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, Ack, Syn, Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ) of
	true ->
            StateNew1  = storeState_Payload(Direction, StateNew0, SEG_SEQ, PayloadLength, <<Payload:PayloadLength/binary>>),
	    StateNew2  = checkPayloadReceptionBuffer(not(Direction), Ack, SEG_ACK, Syn or Fin, StateNew1),
	    StateNew3 = storeState_SND_UNA(Direction, StateNew2, SEG_ACK, Ack),
	    StateNew4  = storeState_SND_WND(Direction, StateNew3, SEG_WND),
	    StateNew   = forward_stream_ack_payload_store(Direction, Fin, Source, Destination, StateNew4),
	    NextStateName = state_closing,
            log_initiator_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew);
	false ->
	    StateNew = State,
	    NextStateName = state_fin_wait_1,
            log_initiator_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew)
    end,
    {next_state, NextStateName, StateNew};

state_fin_wait_1(
  {packet_with_addressing,
   {_Ack, _Syn, _Fin, _Rst = true, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Rst by connection close initiator
   {{Close_initiator_address, Close_initiator_port} = Source,
    {Close_responder_address, Close_responder_port} = Destination},
   _DLT, _Time, _Len, _Packet, PayloadLength}, State) when
      State#state.close_responder_address == Close_responder_address,
      State#state.close_responder_port    == Close_responder_port,
      State#state.close_initiator_address == Close_initiator_address,
      State#state.close_initiator_port    == Close_initiator_port ->
    Direction = determine_Direction({Source, Destination} , State),
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, _Ack, _Syn, _Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ, PayloadLength) of
	true ->
            StateNew = StateNew0,
	    NextStateName = state_time_wait;
        false ->
            %%error_logger:warning_msg("Warning!!!!Direction:~w, SEG_SEQ: ~w, PayloadLength ~w, RCV_NXT: ~w, RCV_WND: ~w~n", [Direction, SEG_SEQ, PayloadLength, State#state.responder_RCV_NXT, calculate_window(Direction, State)]),
            StateNew = StateNew0,
            NextStateName = state_fin_wait_1,
            log_initiator_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew)
    end,
    {next_state, NextStateName, StateNew, 10000};

state_fin_wait_1(
  {packet_with_addressing,
   {_Ack = true, _Syn = true, _Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Syn-Ack repeatition by connection initiator, connection responder had responded with FIN
   {{Close_responder_address, Close_responder_port} = Source},
    {Close_initiator_address, Close_initiator_port} = Destination,
   _DLT, _Time, _Len, _Packet, PayloadLength}, State) when
      State#state.close_responder_address == Close_responder_address,
      State#state.close_responder_port    == Close_responder_port,
      State#state.close_initiator_address == Close_initiator_address,
      State#state.close_initiator_port    == Close_initiator_port ->
    Direction = determine_Direction({Source, Destination} , State),
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, _Ack, _Syn, _Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ, PayloadLength) of
	true ->
            StateNew = StateNew0,
	    NextStateName = state_fin_wait_1;
        false ->
            %%error_logger:warning_msg("Warning!!!!Direction:~w, SEG_SEQ: ~w, PayloadLength ~w, RCV_NXT: ~w, RCV_WND: ~w~n", [Direction, SEG_SEQ, PayloadLength, State#state.responder_RCV_NXT, calculate_window(Direction, State)]),
            StateNew = StateNew0,
            NextStateName = state_fin_wait_1,
            log_initiator_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew)
    end,
    {next_state, NextStateName, StateNew, 10000};

state_fin_wait_1(
  {packet_with_addressing,
   {_Ack , _Syn , _Fin, _Rst = true, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Rst by connection close responder
   {{Close_responder_address, Close_responder_port} = Source,
    {Close_initiator_address, Close_initiator_port} = Destination},
   _DLT, _Time, _Len, _Packet, PayloadLength}, State) when
      State#state.close_responder_address == Close_responder_address,
      State#state.close_responder_port    == Close_responder_port,
      State#state.close_initiator_address == Close_initiator_address,
      State#state.close_initiator_port    == Close_initiator_port ->
    Direction = determine_Direction({Source, Destination} , State),
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, _Ack, _Syn, _Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ, PayloadLength) of
	true ->
            StateNew = StateNew0,
	    NextStateName = state_time_wait;
        false ->
            %%error_logger:warning_msg("Warning!!!!Direction:~w, SEG_SEQ: ~w, PayloadLength ~w, RCV_NXT: ~w, RCV_WND: ~w~n", [Direction, SEG_SEQ, PayloadLength, State#state.responder_RCV_NXT, calculate_window(Direction, State)]),
            StateNew = StateNew0,
            NextStateName = state_fin_wait_1,
            log_initiator_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew)
    end,
    {next_state, NextStateName, StateNew, 10000}.

state_fin_wait_2(
  {packet_with_addressing,
   {Ack = true, Syn = false, Fin = false, _Rst = false, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Ack retransmission from close initiator
   {{Close_initiator_address, Close_initiator_port} = Destination,
    {Close_responder_address, Close_responder_port} = Source},
   _DLT, _Time, _Len, Packet, PayloadLength}, State) when
      State#state.close_responder_address == Close_responder_address,
      State#state.close_responder_port    == Close_responder_port,
      State#state.close_initiator_address == Close_initiator_address,
      State#state.close_initiator_port    == Close_initiator_port ->
    Direction = determine_Direction({Source, Destination} , State),
    [_EtherIgnore, _IP, _TCP, Payload] = Packet,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, Ack, Syn, Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ) of
	true ->
            StateNew1  = storeState_Payload(Direction, StateNew0, SEG_SEQ, PayloadLength, <<Payload:PayloadLength/binary>>),
	    StateNew2  = checkPayloadReceptionBuffer(not(Direction), Ack, SEG_ACK, Syn or Fin, StateNew1),
	    StateNew3 = storeState_SND_UNA(Direction, StateNew2, SEG_ACK, Ack),
	    StateNew4  = storeState_SND_WND(Direction, StateNew3, SEG_WND),
	    StateNew   = forward_stream_ack_payload_store(Direction, Fin, Source, Destination, StateNew4),
	    NextStateName = state_fin_wait_2;
        false ->
            StateNew = State,
            NextStateName = state_fin_wait_2
    end,
    {next_state, NextStateName, StateNew};

state_fin_wait_2(
  {packet_with_addressing,
   {Ack = true, Syn = false, Fin = false, _Rst = false, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Ack retransmission from close responder
   {{Close_responder_address, Close_responder_port} = Source,
    {Close_initiator_address, Close_initiator_port} = Destination},
   _DLT, _Time, _Len, Packet, PayloadLength}, State) when
      State#state.close_responder_address == Close_responder_address,
      State#state.close_responder_port    == Close_responder_port,
      State#state.close_initiator_address == Close_initiator_address,
      State#state.close_initiator_port    == Close_initiator_port ->
    Direction = determine_Direction({Source, Destination} , State),
    [_EtherIgnore, _IP, _TCP, Payload] = Packet,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, Ack, Syn, Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ) of
	true ->
            StateNew1  = storeState_Payload(Direction, StateNew0, SEG_SEQ, PayloadLength, <<Payload:PayloadLength/binary>>),
	    StateNew2  = checkPayloadReceptionBuffer(not(Direction), Ack, SEG_ACK, Syn or Fin, StateNew1),
	    StateNew3 = storeState_SND_UNA(Direction, StateNew2, SEG_ACK, Ack),
	    StateNew4  = storeState_SND_WND(Direction, StateNew3, SEG_WND),
	    StateNew   = forward_stream_ack_payload_store(Direction, Fin, Source, Destination, StateNew4),
	    NextStateName = state_fin_wait_2;
        false ->
            StateNew = State,
            NextStateName = state_fin_wait_2
    end,
    {next_state, NextStateName, StateNew};

state_fin_wait_2(
  {packet_with_addressing,
   {Ack = true, Syn = false, Fin = true, _Rst = false, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Fin-Ack retransmission
   {{Close_initiator_address, Close_initiator_port} = Source,
    {Close_responder_address, Close_responder_port} = Destination},
   _DLT, _Time, _Len, Packet, PayloadLength}, State) when
      State#state.close_responder_address == Close_responder_address,
      State#state.close_responder_port    == Close_responder_port,
      State#state.close_initiator_address == Close_initiator_address,
      State#state.close_initiator_port    == Close_initiator_port ->
    Direction = determine_Direction({Source, Destination} , State),
    [_EtherIgnore, _IP, _TCP, Payload] = Packet,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, Ack, Syn, Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ) of
	true ->
            StateNew1  = storeState_Payload(Direction, StateNew0, SEG_SEQ, PayloadLength, <<Payload:PayloadLength/binary>>),
	    StateNew2  = checkPayloadReceptionBuffer(not(Direction), Ack, SEG_ACK, Syn or Fin, StateNew1),
	    StateNew3 = storeState_SND_UNA(Direction, StateNew2, SEG_ACK, Ack),
	    StateNew4  = storeState_SND_WND(Direction, StateNew3, SEG_WND),
	    StateNew   = forward_stream_ack_payload_store(Direction, Fin, Source, Destination, StateNew4),
	    NextStateName = state_fin_wait_2;
        false ->
            StateNew = State,
            NextStateName = state_fin_wait_2
    end,
    {next_state, NextStateName, StateNew};

state_fin_wait_2(
  {packet_with_addressing,
   {Ack = false, Syn = false, Fin = true, _Rst = false, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Fin, payload optional
   {{Close_responder_address, Close_responder_port} = Source,
    {Close_initiator_address, Close_initiator_port} = Destination},
   _DLT, _Time, _Len, Packet, PayloadLength}, State) when
      State#state.close_responder_address == Close_responder_address,
      State#state.close_responder_port    == Close_responder_port,
      State#state.close_initiator_address == Close_initiator_address,
      State#state.close_initiator_port    == Close_initiator_port ->
    Direction = determine_Direction({Source, Destination} , State),
    [_EtherIgnore, _IP, _TCP, Payload] = Packet,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, Ack, Syn, Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ) of
	true ->
            StateNew1  = storeState_Payload(Direction, StateNew0, SEG_SEQ, PayloadLength, <<Payload:PayloadLength/binary>>),
	    StateNew2  = checkPayloadReceptionBuffer(not(Direction), Ack, SEG_ACK, Syn or Fin, StateNew1),
	    StateNew3 = storeState_SND_UNA(Direction, StateNew2, SEG_ACK, Ack),
	    StateNew4  = storeState_SND_WND(Direction, StateNew3, SEG_WND),
	    StateNew   = forward_stream_ack_payload_store(Direction, Fin, Source, Destination, StateNew4),
            NextStateName = state_fin_ack_fin_wait;
	false ->
	    StateNew = State,
	    NextStateName = state_fin_wait_2
    end,
    {next_state, NextStateName, StateNew};

state_fin_wait_2(
  {packet_with_addressing,
   {Ack = true, Syn = false, Fin = true, _Rst = false, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Fin-Ack, payload
   {{Close_responder_address, Close_responder_port} = Source,
    {Close_initiator_address, Close_initiator_port} = Destination},
   _DLT, _Time, _Len, Packet, PayloadLength}, State) when
      State#state.close_responder_address == Close_responder_address,
      State#state.close_responder_port    == Close_responder_port,
      State#state.close_initiator_address == Close_initiator_address,
      State#state.close_initiator_port    == Close_initiator_port ->
    Direction = determine_Direction({Source, Destination} , State),
    [_EtherIgnore, _IP, _TCP, Payload] = Packet,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, Ack, Syn, Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ) of
	true ->
            StateNew1  = storeState_Payload(Direction, StateNew0, SEG_SEQ, PayloadLength, <<Payload:PayloadLength/binary>>),
	    StateNew2  = checkPayloadReceptionBuffer(not(Direction), Ack, SEG_ACK, Syn or Fin, StateNew1),
	    StateNew3 = storeState_SND_UNA(Direction, StateNew2, SEG_ACK, Ack),
	    StateNew4  = storeState_SND_WND(Direction, StateNew3, SEG_WND),
	    StateNew   = forward_stream_ack_payload_store(Direction, Fin, Source, Destination, StateNew4),
            NextStateName = state_fin_ack_fin_wait;
	false ->
	    StateNew = State,
	    NextStateName = state_fin_wait_2
    end,
    {next_state, NextStateName, StateNew};

state_fin_wait_2(
  {packet_with_addressing,
   {_Ack, _Syn, _Fin, _Rst = true, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Rst by connection close initiator
   {{Close_initiator_address, Close_initiator_port} = Source,
    {Close_responder_address, Close_responder_port} = Destination},
   _DLT, _Time, _Len, _Packet, PayloadLength}, State) when
      State#state.close_responder_address == Close_responder_address,
      State#state.close_responder_port    == Close_responder_port,
      State#state.close_initiator_address == Close_initiator_address,
      State#state.close_initiator_port    == Close_initiator_port ->
    Direction = determine_Direction({Source, Destination} , State),
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, _Ack, _Syn, _Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ, PayloadLength) of
	true ->
            StateNew = StateNew0,
	    NextStateName = state_time_wait;
        false ->
            %%error_logger:warning_msg("Warning!!!!Direction:~w, SEG_SEQ: ~w, PayloadLength ~w, RCV_NXT: ~w, RCV_WND: ~w~n", [Direction, SEG_SEQ, PayloadLength, State#state.responder_RCV_NXT, calculate_window(Direction, State)]),
            StateNew = StateNew0,
            NextStateName = state_fin_wait_2,
            log_initiator_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew)
    end,
    {next_state, NextStateName, StateNew, 10000};

state_fin_wait_2(
  {packet_with_addressing,
   {_Ack , _Syn , _Fin, _Rst = true, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Rst by connection close responder
   {{Close_responder_address, Close_responder_port} = Source,
    {Close_initiator_address, Close_initiator_port} = Destination},
   _DLT, _Time, _Len, _Packet, PayloadLength}, State) when
      State#state.close_responder_address == Close_responder_address,
      State#state.close_responder_port    == Close_responder_port,
      State#state.close_initiator_address == Close_initiator_address,
      State#state.close_initiator_port    == Close_initiator_port ->
    Direction = determine_Direction({Source, Destination} , State),
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, _Ack, _Syn, _Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ, PayloadLength) of
	true ->
            StateNew = StateNew0,
	    NextStateName = state_time_wait;
        false ->
            %%error_logger:warning_msg("Warning!!!!Direction:~w, SEG_SEQ: ~w, PayloadLength ~w, RCV_NXT: ~w, RCV_WND: ~w~n", [Direction, SEG_SEQ, PayloadLength, State#state.responder_RCV_NXT, calculate_window(Direction, State)]),
            StateNew = StateNew0,
            NextStateName = state_fin_wait_2,
            log_initiator_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew)
    end,
    {next_state, NextStateName, StateNew, 10000}.

state_fin_fin_wait(
  {packet_with_addressing,
   {Ack = true, Syn = false, Fin = false, _Rst = false, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Ack
   {{Close_initiator_address, Close_initiator_port} = Source,
    {Close_responder_address, Close_responder_port} = Destination},
   _DLT, _Time, _Len, Packet, PayloadLength}, State) when
      State#state.close_responder_address == Close_responder_address,
      State#state.close_responder_port    == Close_responder_port,
      State#state.close_initiator_address == Close_initiator_address,
      State#state.close_initiator_port    == Close_initiator_port ->
    Direction = determine_Direction({Source, Destination} , State),
    [_EtherIgnore, _IP, _TCP, Payload] = Packet,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, Ack, Syn, Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ) of
	true ->
            StateNew1  = storeState_Payload(Direction, StateNew0, SEG_SEQ, PayloadLength, <<Payload:PayloadLength/binary>>),
	    StateNew2  = checkPayloadReceptionBuffer(not(Direction), Ack, SEG_ACK, Syn or Fin, StateNew1),
	    StateNew3 = storeState_SND_UNA(Direction, StateNew2, SEG_ACK, Ack),
	    StateNew4  = storeState_SND_WND(Direction, StateNew3, SEG_WND),
	    StateNew   = forward_stream_ack_payload_store(Direction, Fin, Source, Destination, StateNew4),
	    NextStateName = state_closing;
	false ->
	    StateNew = State,
	    NextStateName = state_fin_fin_wait
    end,
    {next_state, NextStateName, StateNew};

state_fin_fin_wait(
  {packet_with_addressing,
   {_Ack, _Syn, _Fin, _Rst = true, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Rst
   {{Initiator_address, Initiator_port},
    {Responder_address, Responder_port}},
   _DLT, _Time, _Len, _Packet, PayloadLength}, State) when
      State#state.responder_address == Responder_address,
      State#state.responder_port    == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port    == Initiator_port ->
    Direction=true,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, _Ack, _Syn, _Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ, PayloadLength) of
	true ->
            StateNew = StateNew0,
	    NextStateName = state_time_wait;
        false ->
            %%error_logger:warning_msg("Warning!!!!Direction:~w, SEG_SEQ: ~w, PayloadLength ~w, RCV_NXT: ~w, RCV_WND: ~w~n", [Direction, SEG_SEQ, PayloadLength, State#state.responder_RCV_NXT, calculate_window(Direction, State)]),
            StateNew = StateNew0,
            NextStateName = state_fin_fin_wait,
            log_initiator_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew)
    end,
    {next_state, NextStateName, StateNew, 10000};

state_fin_fin_wait(
  {packet_with_addressing,
   {_Ack, _Syn, _Fin, _Rst = true, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Rst
   {{Responder_address, Responder_port},
    {Initiator_address, Initiator_port}},
   _DLT, _Time, _Len, _Packet, PayloadLength}, State) when
      State#state.responder_address == Responder_address,
      State#state.responder_port    == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port    == Initiator_port ->
    Direction=false,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, _Ack, _Syn, _Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ, PayloadLength) of
	true ->
            StateNew = StateNew0,
	    NextStateName = state_time_wait;
        false ->
            %%error_logger:warning_msg("Warning!!!!Direction:~w, SEG_SEQ: ~w, PayloadLength ~w, RCV_NXT: ~w, RCV_WND: ~w~n", [Direction, SEG_SEQ, PayloadLength, State#state.responder_RCV_NXT, calculate_window(Direction, State)]),
            StateNew = StateNew0,
            NextStateName = state_fin_fin_wait,
            log_initiator_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew)
    end,
    {next_state, NextStateName, StateNew, 10000}.

state_fin_finack_wait(
  {packet_with_addressing,
   {Ack = true, Syn = false, Fin = false, _Rst = false, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Ack
   {{Close_initiator_address, Close_initiator_port} = Source,
    {Close_responder_address, Close_responder_port} = Destination},
   _DLT, _Time, _Len, Packet, PayloadLength}, State) when
      State#state.close_responder_address == Close_responder_address,
      State#state.close_responder_port    == Close_responder_port,
      State#state.close_initiator_address == Close_initiator_address,
      State#state.close_initiator_port    == Close_initiator_port ->
    Direction = determine_Direction({Source, Destination} , State),
    [_EtherIgnore, _IP, _TCP, Payload] = Packet,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, Ack, Syn, Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ) of
	true ->
            StateNew1  = storeState_Payload(Direction, StateNew0, SEG_SEQ, PayloadLength, <<Payload:PayloadLength/binary>>),
	    StateNew2  = checkPayloadReceptionBuffer(not(Direction), Ack, SEG_ACK, Syn or Fin, StateNew1),
	    StateNew3 = storeState_SND_UNA(Direction, StateNew2, SEG_ACK, Ack),
	    StateNew4  = storeState_SND_WND(Direction, StateNew3, SEG_WND),
	    StateNew   = forward_stream_ack_payload_store(Direction, Fin, Source, Destination, StateNew4),
            {next_state, state_time_wait, StateNew, 10000};
        false ->
            StateNew = State,
            {next_state, state_fin_finack_wait, StateNew}
    end;

state_fin_finack_wait(
  {packet_with_addressing,
   {Ack = true, Syn = false, Fin = false, _Rst = false, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Ack
   {{Close_responder_address, Close_responder_port} = Source,
    {Close_initiator_address, Close_initiator_port} = Destination},
   _DLT, _Time, _Len, Packet, PayloadLength}, State) when
      State#state.close_responder_address == Close_responder_address,
      State#state.close_responder_port    == Close_responder_port,
      State#state.close_initiator_address == Close_initiator_address,
      State#state.close_initiator_port    == Close_initiator_port ->
    Direction = determine_Direction({Source, Destination} , State),
    [_EtherIgnore, _IP, _TCP, Payload] = Packet,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, Ack, Syn, Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ) of
	true ->
            StateNew1  = storeState_Payload(Direction, StateNew0, SEG_SEQ, PayloadLength, <<Payload:PayloadLength/binary>>),
	    StateNew2  = checkPayloadReceptionBuffer(not(Direction), Ack, SEG_ACK, Syn or Fin, StateNew1),
	    StateNew3 = storeState_SND_UNA(Direction, StateNew2, SEG_ACK, Ack),
	    StateNew4  = storeState_SND_WND(Direction, StateNew3, SEG_WND),
	    StateNew   = forward_stream_ack_payload_store(Direction, Fin, Source, Destination, StateNew4),
            {next_state, state_fin_finack_wait, StateNew};
        false ->
            StateNew = State,
            {next_state, state_fin_finack_wait, StateNew}
    end;

state_fin_finack_wait(
  {packet_with_addressing,
   {Ack = true, Syn = false, Fin = true, _Rst = false, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Fin-Ack retransmission by close initiator
   {{Close_initiator_address, Close_initiator_port} = Source,
    {Close_responder_address, Close_responder_port} = Destination},
   _DLT, _Time, _Len, Packet, PayloadLength}, State) when
      State#state.close_responder_address == Close_responder_address,
      State#state.close_responder_port    == Close_responder_port,
      State#state.close_initiator_address == Close_initiator_address,
      State#state.close_initiator_port    == Close_initiator_port ->
    Direction = determine_Direction({Source, Destination} , State),
    [_EtherIgnore, _IP, _TCP, Payload] = Packet,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, Ack, Syn, Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ) of
	true ->
            StateNew1  = storeState_Payload(Direction, StateNew0, SEG_SEQ, PayloadLength, <<Payload:PayloadLength/binary>>),
	    StateNew2  = checkPayloadReceptionBuffer(not(Direction), Ack, SEG_ACK, Syn or Fin, StateNew1),
	    StateNew3 = storeState_SND_UNA(Direction, StateNew2, SEG_ACK, Ack),
	    StateNew4  = storeState_SND_WND(Direction, StateNew3, SEG_WND),
	    StateNew   = forward_stream_ack_payload_store(Direction, Fin, Source, Destination, StateNew4),
	    NextStateName = state_fin_finack_wait,
            log_initiator_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew);
        false ->
            StateNew = State,
            NextStateName = state_fin_finack_wait,
            log_initiator_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew)
    end,
    {next_state, NextStateName, StateNew};

state_fin_finack_wait(
  {packet_with_addressing,
   {Ack = true, Syn = false, Fin = true, _Rst = false, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Fin-Ack retransmission by close responder
   {{Close_responder_address, Close_responder_port} = Source,
    {Close_initiator_address, Close_initiator_port} = Destination},
   _DLT, _Time, _Len, Packet, PayloadLength}, State) when
      State#state.close_responder_address == Close_responder_address,
      State#state.close_responder_port    == Close_responder_port,
      State#state.close_initiator_address == Close_initiator_address,
      State#state.close_initiator_port    == Close_initiator_port ->
    Direction = determine_Direction({Source, Destination} , State),
    [_EtherIgnore, _IP, _TCP, Payload] = Packet,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, Ack, Syn, Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ) of
	true ->
            StateNew1  = storeState_Payload(Direction, StateNew0, SEG_SEQ, PayloadLength, <<Payload:PayloadLength/binary>>),
	    StateNew2  = checkPayloadReceptionBuffer(not(Direction), Ack, SEG_ACK, Syn or Fin, StateNew1),
	    StateNew3 = storeState_SND_UNA(Direction, StateNew2, SEG_ACK, Ack),
	    StateNew4  = storeState_SND_WND(Direction, StateNew3, SEG_WND),
	    StateNew   = forward_stream_ack_payload_store(Direction, Fin, Source, Destination, StateNew4),
	    NextStateName = state_fin_finack_wait,
            log_initiator_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew);
        false ->
            StateNew = State,
            NextStateName = state_fin_finack_wait,
            log_initiator_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew)
    end,
    {next_state, NextStateName, StateNew};

state_fin_finack_wait(
  {packet_with_addressing,
   {_Ack, _Syn, _Fin, _Rst = true, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Rst
   {{Initiator_address, Initiator_port},
    {Responder_address, Responder_port}},
   _DLT, _Time, _Len, _Packet, PayloadLength}, State) when
      State#state.responder_address == Responder_address,
      State#state.responder_port    == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port    == Initiator_port ->
    Direction=true,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, _Ack, _Syn, _Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ, PayloadLength) of
	true ->
            StateNew = StateNew0,
	    NextStateName = state_time_wait;
        false ->
            %%error_logger:warning_msg("Warning!!!!Direction:~w, SEG_SEQ: ~w, PayloadLength ~w, RCV_NXT: ~w, RCV_WND: ~w~n", [Direction, SEG_SEQ, PayloadLength, State#state.responder_RCV_NXT, calculate_window(Direction, State)]),
            StateNew = StateNew0,
            NextStateName = state_fin_finack_wait,
            log_initiator_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew)
    end,
    {next_state, NextStateName, StateNew, 10000};

state_fin_finack_wait(
  {packet_with_addressing,
   {_Ack, _Syn, _Fin, _Rst = true, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Rst
   {{Responder_address, Responder_port},
    {Initiator_address, Initiator_port}},
   _DLT, _Time, _Len, _Packet, PayloadLength}, State) when
      State#state.responder_address == Responder_address,
      State#state.responder_port    == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port    == Initiator_port ->
    Direction=false,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, _Ack, _Syn, _Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ, PayloadLength) of
	true ->
            StateNew = StateNew0,
	    NextStateName = state_time_wait;
        false ->
            %%error_logger:warning_msg("Warning!!!!Direction:~w, SEG_SEQ: ~w, PayloadLength ~w, RCV_NXT: ~w, RCV_WND: ~w~n", [Direction, SEG_SEQ, PayloadLength, State#state.responder_RCV_NXT, calculate_window(Direction, State)]),
            StateNew = StateNew0,
            NextStateName = state_fin_finack_wait,
            log_initiator_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew)
    end,
    {next_state, NextStateName, StateNew, 10000}.

state_fin_ack_fin_wait(
  {packet_with_addressing,
   {Ack = true, Syn = false, Fin = false, _Rst = false, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Ack
   {{Close_initiator_address, Close_initiator_port} = Source,
    {Close_responder_address, Close_responder_port} = Destination},
   _DLT, _Time, _Len, Packet, PayloadLength}, State) when
      State#state.close_responder_address == Close_responder_address,
      State#state.close_responder_port    == Close_responder_port,
      State#state.close_initiator_address == Close_initiator_address,
      State#state.close_initiator_port    == Close_initiator_port ->
    Direction = determine_Direction({Source, Destination} , State),
    [_EtherIgnore, _IP, _TCP, Payload] = Packet,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, Ack, Syn, Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ) of
	true ->
            StateNew1  = storeState_Payload(Direction, StateNew0, SEG_SEQ, PayloadLength, <<Payload:PayloadLength/binary>>),
	    StateNew2  = checkPayloadReceptionBuffer(not(Direction), Ack, SEG_ACK, Syn or Fin, StateNew1),
	    StateNew3 = storeState_SND_UNA(Direction, StateNew2, SEG_ACK, Ack),
	    StateNew4  = storeState_SND_WND(Direction, StateNew3, SEG_WND),
	    StateNew   = forward_stream_ack_payload_store(Direction, Fin, Source, Destination, StateNew4),
            {next_state, state_time_wait, StateNew, 1000};
        false ->
            StateNew = State,
            {next_state, fin_ack_fin_wait, StateNew}
    end;

state_fin_ack_fin_wait(
  {packet_with_addressing,
   {Ack = true, Syn = false, Fin = false, _Rst = false, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Ack
   {{Close_responder_address, Close_responder_port} = Source,
    {Close_initiator_address, Close_initiator_port} = Destination},
   _DLT, _Time, _Len, Packet, PayloadLength}, State) when
      State#state.close_responder_address == Close_responder_address,
      State#state.close_responder_port    == Close_responder_port,
      State#state.close_initiator_address == Close_initiator_address,
      State#state.close_initiator_port    == Close_initiator_port ->
    Direction = determine_Direction({Source, Destination} , State),
    [_EtherIgnore, _IP, _TCP, Payload] = Packet,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, Ack, Syn, Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ) of
	true ->
            StateNew1  = storeState_Payload(Direction, StateNew0, SEG_SEQ, PayloadLength, <<Payload:PayloadLength/binary>>),
	    StateNew2  = checkPayloadReceptionBuffer(not(Direction), Ack, SEG_ACK, Syn or Fin, StateNew1),
	    StateNew3 = storeState_SND_UNA(Direction, StateNew2, SEG_ACK, Ack),
	    StateNew4  = storeState_SND_WND(Direction, StateNew3, SEG_WND),
	    StateNew   = forward_stream_ack_payload_store(Direction, Fin, Source, Destination, StateNew4),
            {next_state, fin_ack_fin_wait, StateNew};
        false ->
            StateNew = State,
            {next_state, fin_ack_fin_wait, StateNew}
    end;


state_fin_ack_fin_wait(
  {packet_with_addressing,
   {_Ack, _Syn, _Fin, _Rst = true, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Rst
   {{Initiator_address, Initiator_port},
    {Responder_address, Responder_port}},
   _DLT, _Time, _Len, _Packet, PayloadLength}, State) when
      State#state.responder_address == Responder_address,
      State#state.responder_port    == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port    == Initiator_port ->
    Direction=true,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, _Ack, _Syn, _Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ, PayloadLength) of
	true ->
            StateNew = StateNew0,
	    NextStateName = state_time_wait;
        false ->
	    %%error_logger:warning_msg("Warning!!!!Direction:~w, SEG_SEQ: ~w, PayloadLength ~w, RCV_NXT: ~w, RCV_WND: ~w~n", [Direction, SEG_SEQ, PayloadLength, State#state.responder_RCV_NXT, calculate_window(Direction, State)]),
            StateNew = StateNew0,
            NextStateName = state_fin_ack_fin_wait,
            log_initiator_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew)
    end,
    {next_state, NextStateName, StateNew, 10000};

state_fin_ack_fin_wait(
  {packet_with_addressing,
   {_Ack, _Syn, _Fin, _Rst = true, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Rst
   {{Responder_address, Responder_port},
    {Initiator_address, Initiator_port}},
   _DLT, _Time, _Len, _Packet, PayloadLength}, State) when
      State#state.responder_address == Responder_address,
      State#state.responder_port    == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port    == Initiator_port ->
    Direction=false,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, _Ack, _Syn, _Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ, PayloadLength) of
	true ->
            StateNew = StateNew0,
	    NextStateName = state_time_wait;
        false ->
	    %%error_logger:warning_msg("Warning!!!!Direction:~w, SEG_SEQ: ~w, PayloadLength ~w, RCV_NXT: ~w, RCV_WND: ~w~n", [Direction, SEG_SEQ, PayloadLength, State#state.responder_RCV_NXT, calculate_window(Direction, State)]),
            StateNew = StateNew0,
            NextStateName = state_fin_ack_fin_wait,
            log_initiator_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew)
    end,
    {next_state, NextStateName, StateNew, 10000}.

state_closing(
  {packet_with_addressing,
   {Ack = true, Syn = false, Fin = false, _Rst = false, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Ack
   {{Close_initiator_address, Close_initiator_port} = Source,
    {Close_responder_address, Close_responder_port} = Destination},
   _DLT, _Time, _Len, Packet, PayloadLength}, State) when
      State#state.close_responder_address == Close_responder_address,
      State#state.close_responder_port    == Close_responder_port,
      State#state.close_initiator_address == Close_initiator_address,
      State#state.close_initiator_port    == Close_initiator_port ->
    Direction = determine_Direction({Source, Destination} , State),
    [_EtherIgnore, _IP, _TCP, Payload] = Packet,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, Ack, Syn, Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ) of
	true ->
            StateNew1  = storeState_Payload(Direction, StateNew0, SEG_SEQ, PayloadLength, <<Payload:PayloadLength/binary>>),
	    StateNew2  = checkPayloadReceptionBuffer(not(Direction), Ack, SEG_ACK, Syn or Fin, StateNew1),
	    StateNew3 = storeState_SND_UNA(Direction, StateNew2, SEG_ACK, Ack),
	    StateNew4  = storeState_SND_WND(Direction, StateNew3, SEG_WND),
	    StateNew   = forward_stream_ack_payload_store(Direction, Fin, Source, Destination, StateNew4),
	    NextStateName = state_closing,
            {next_state, NextStateName, StateNew};
	false ->
	    StateNew = State,
	    NextStateName = state_time_wait,
	    {next_state, NextStateName, StateNew, 10000}
    end;

state_closing(
  {packet_with_addressing,
   {_Ack, _Syn, _Fin, _Rst = true, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Rst
   {{Initiator_address, Initiator_port},
    {Responder_address, Responder_port}},
   _DLT, _Time, _Len, _Packet, PayloadLength}, State) when
      State#state.responder_address == Responder_address,
      State#state.responder_port    == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port    == Initiator_port ->
    Direction=true,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, _Ack, _Syn, _Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ, PayloadLength) of
	true ->
            StateNew = StateNew0,
	    NextStateName = state_time_wait;
        false ->
	    %%error_logger:warning_msg("Warning!!!!Direction:~w, SEG_SEQ: ~w, PayloadLength ~w, RCV_NXT: ~w, RCV_WND: ~w~n", [Direction, SEG_SEQ, PayloadLength, State#state.responder_RCV_NXT, calculate_window(Direction, State)]),
            StateNew = StateNew0,
            NextStateName = state_closing,
            log_initiator_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew)
    end,
    {next_state, NextStateName, StateNew, 10000};

state_closing(
  {packet_with_addressing,
   {_Ack, _Syn, _Fin, _Rst = true, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Rst
   {{Responder_address, Responder_port},
    {Initiator_address, Initiator_port}},
   _DLT, _Time, _Len, _Packet, PayloadLength}, State) when
      State#state.responder_address == Responder_address,
      State#state.responder_port    == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port    == Initiator_port ->
    Direction=false,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, _Ack, _Syn, _Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ, PayloadLength) of
	true ->
            StateNew = StateNew0,
	    NextStateName = state_time_wait;
        false ->
	    %%error_logger:warning_msg("Warning!!!!Direction:~w, SEG_SEQ: ~w, PayloadLength ~w, RCV_NXT: ~w, RCV_WND: ~w~n", [Direction, SEG_SEQ, PayloadLength, State#state.responder_RCV_NXT, calculate_window(Direction, State)]),
            StateNew = StateNew0,
            NextStateName = state_closing,
            log_initiator_responder(NextStateName, SEG_SEQ, SEG_ACK, SEG_WND, StateNew)
    end,
    {next_state, NextStateName, StateNew, 10000}.

state_time_wait(
  {packet_with_addressing,
   {Ack = true, Syn = false, Fin = false, _Rst = false, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Ack retransmission
   {{Close_responder_address, Close_responder_port} = Source,
    {Close_initiator_address, Close_initiator_port} = Destination},
   _DLT, _Time, _Len, Packet, PayloadLength}, State) when
      State#state.close_responder_address == Close_responder_address,
      State#state.close_responder_port    == Close_responder_port,
      State#state.close_initiator_address == Close_initiator_address,
      State#state.close_initiator_port    == Close_initiator_port ->
    Direction = determine_Direction({Source, Destination} , State),
    [_EtherIgnore, _IP, _TCP, Payload] = Packet,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, Ack, Syn, Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ) of
	true ->
            StateNew1  = storeState_Payload(Direction, StateNew0, SEG_SEQ, PayloadLength, <<Payload:PayloadLength/binary>>),
	    StateNew2  = checkPayloadReceptionBuffer(not(Direction), Ack, SEG_ACK, Syn or Fin, StateNew1),
	    StateNew3 = storeState_SND_UNA(Direction, StateNew2, SEG_ACK, Ack),
	    StateNew4  = storeState_SND_WND(Direction, StateNew3, SEG_WND),
	    StateNew   = forward_stream_ack_payload_store(Direction, Fin, Source, Destination, StateNew4),
            NextStateName = state_time_wait;
	false ->
	    StateNew = State,
	    NextStateName = state_time_wait
    end,
    {next_state, NextStateName, StateNew, 10000};

state_time_wait(
  {packet_with_addressing,
   {Ack = true, Syn = false, Fin = true, _Rst = false, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Fin-Ack retransmission
   {{Close_responder_address, Close_responder_port} = Source,
    {Close_initiator_address, Close_initiator_port} = Destination},
   _DLT, _Time, _Len, Packet, PayloadLength}, State) when
      State#state.close_responder_address == Close_responder_address,
      State#state.close_responder_port    == Close_responder_port,
      State#state.close_initiator_address == Close_initiator_address,
      State#state.close_initiator_port    == Close_initiator_port ->
    Direction = determine_Direction({Source, Destination} , State),
    [_EtherIgnore, _IP, _TCP, Payload] = Packet,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, Ack, Syn, Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ) of
	true ->
            StateNew1  = storeState_Payload(Direction, StateNew0, SEG_SEQ, PayloadLength, <<Payload:PayloadLength/binary>>),
	    StateNew2  = checkPayloadReceptionBuffer(not(Direction), Ack, SEG_ACK, Syn or Fin, StateNew1),
	    StateNew3 = storeState_SND_UNA(Direction, StateNew2, SEG_ACK, Ack),
	    StateNew4  = storeState_SND_WND(Direction, StateNew3, SEG_WND),
	    StateNew   = forward_stream_ack_payload_store(Direction, Fin, Source, Destination, StateNew4),
	    NextStateName = state_time_wait;
	false ->
	    StateNew = State,
	    NextStateName = state_time_wait
    end,
    {next_state, NextStateName, StateNew, 10000};

state_time_wait(
  {packet_with_addressing,
   {Ack = true, Syn = false, Fin = false, _Rst = false, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, %Ack
   {{Initiator_address, Initiator_port} = Source,
    {Responder_address, Responder_port} = Destination},
   _DLT, _Time, _Len, Packet, PayloadLength}, State) when
      State#state.responder_address == Responder_address,
      State#state.responder_port    == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port    == Initiator_port ->
    Direction = determine_Direction({Source, Destination} , State),
    [_EtherIgnore, _IP, _TCP, Payload] = Packet,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, Ack, Syn, Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ) of
	true ->
            StateNew1  = storeState_Payload(Direction, StateNew0, SEG_SEQ, PayloadLength, <<Payload:PayloadLength/binary>>),
	    StateNew2  = checkPayloadReceptionBuffer(not(Direction), Ack, SEG_ACK, Syn or Fin, StateNew1),
	    StateNew3 = storeState_SND_UNA(Direction, StateNew2, SEG_ACK, Ack),
	    StateNew4  = storeState_SND_WND(Direction, StateNew3, SEG_WND),
	    StateNew   = forward_stream_ack_payload_store(Direction, Fin, Source, Destination, StateNew4),
            NextStateName = state_time_wait;
	false ->
	    StateNew = State,
	    NextStateName = state_time_wait
    end,
    {next_state, NextStateName, StateNew, 10000};

state_time_wait(
  {packet_with_addressing,
   {Ack, Syn = false, Fin = true, _Rst = false, SEG_SEQ, SEG_ACK, SEG_WND, _OPT}, % Fin-Ack / Fin retransmission
   {{Initiator_address, Initiator_port} = Source,
    {Responder_address, Responder_port} = Destination},
   _DLT, _Time, _Len, Packet, PayloadLength}, State) when
      State#state.responder_address == Responder_address,
      State#state.responder_port    == Responder_port,
      State#state.initiator_address == Initiator_address,
      State#state.initiator_port    == Initiator_port ->
    Direction = determine_Direction({Source, Destination} , State),
    [_EtherIgnore, _IP, _TCP, Payload] = Packet,
    StateNew0 = State#state{stack_trace_path= ?DebugBuffer([{?current_function_name(), Direction, Ack, Syn, Fin, _Rst, SEG_SEQ, SEG_ACK, SEG_WND, PayloadLength}|State#state.stack_trace_path])},
    case test_sequence_no_in_window(Direction, StateNew0, SEG_SEQ) of
	true ->
            StateNew1  = storeState_Payload(Direction, StateNew0, SEG_SEQ, PayloadLength, <<Payload:PayloadLength/binary>>),
	    StateNew2  = checkPayloadReceptionBuffer(not(Direction), Ack, SEG_ACK, Syn or Fin, StateNew1),
	    StateNew3 = storeState_SND_UNA(Direction, StateNew2, SEG_ACK, Ack),
	    StateNew4  = storeState_SND_WND(Direction, StateNew3, SEG_WND),
	    StateNew   = forward_stream_ack_payload_store(Direction, Fin, Source, Destination, StateNew4),
            NextStateName = state_time_wait;
	false ->
	    StateNew = State,
	    NextStateName = state_time_wait
    end,
    {next_state, NextStateName, StateNew, 10000};

state_time_wait(
  {packet_with_addressing,
   {_, _, _, true, _SEG_SEQ, _SEG_ACK, _SEG_WND, _OPT}, % Rst
   {{_, _},{_,_}},
   _DLT, _Time, _Len, _Packet, _PayloadLength}, State) ->
    {next_state, state_time_wait, State, 10000};

state_time_wait(timeout, State) ->
    error_logger:warning_msg("Closing Instance: ~p in state time_wait, sent packets: ~p, sent_bytes: ~p~n", [State#state.instance, State#state.sent_packets, State#state.sent_bytes]),
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
terminate(Reason, StateName, State) ->
    stream_server:remove_connection_worker_by_pid(self()),
    error_logger:warning_msg("Reason: ~p, StateName:~p, stack_trace_path: ~p~n", [Reason, StateName, State#state.stack_trace_path]),
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

modulo32bit(Value) when is_integer(Value)->
    Value band 16#FFFFFFFF.

add_modulo_32bit(Seqno, Offset) ->
    modulo32bit(Seqno+Offset).

sequence_no_in_window(_SEG_SEQ, undefined, _RCV_WND, 0) ->
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
    %%error_logger:warning_msg("Forwarding sequence Number from ~p to ~p with Window:~p~n", [SeqB, SeqA, Window]),
    if
	SeqA >= SeqB ->
	    if
		(SeqA - SeqB) =< Window ->
		    SeqA;
		true ->
		    SeqB + Window
	    end;
	true ->
	    Delta = ((SeqA + 16#100000000) - SeqB),
	    if
		Delta =< Window ->
		    SeqA;
		true ->
		    SeqB + Window
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


ack_valid(_SEG_ACK, undefined, _SND_WND) ->
    valid_ack;

ack_valid(SEG_ACK, SND_UNA, SND_WND) ->
    case (modulo32bit(SND_UNA) == modulo32bit(SEG_ACK)) of
	true ->
	    repetition_ack;
	false ->
	    case (smaller(SND_UNA, SEG_ACK) and smaller_or_equal(SEG_ACK, SND_UNA+SND_WND)) of
   		true ->
		    valid_ack;
        	false ->
		    invalid_ack
            end
    end.


test_ack_valid(Direction=true, State, SEG_ACK) ->
    ack_valid(SEG_ACK, State#state.initiator_SND_UNA, calculate_window(Direction, State));

test_ack_valid(Direction=false, State, SEG_ACK) ->
    ack_valid(SEG_ACK, State#state.responder_SND_UNA, calculate_window(Direction, State)).

%% if any of the side did not set the window scale in the options filed, the scale is not used (See RFC 1323)



test_sequence_no_in_window(Direction=true, State, SEG_SEQ) ->
    sequence_no_in_window(SEG_SEQ, State#state.initiator_RCV_NXT,
                          calculate_window(not(Direction), State), 0);

test_sequence_no_in_window(Direction=false, State, SEG_SEQ) ->
    sequence_no_in_window(SEG_SEQ, State#state.responder_RCV_NXT,
                          calculate_window(not(Direction), State), 0).


test_sequence_no_in_window(Direction=true, State, SEG_SEQ, SEG_LEN) ->
    sequence_no_in_window(SEG_SEQ, State#state.initiator_RCV_NXT,
			  calculate_window(not(Direction), State), SEG_LEN);

test_sequence_no_in_window(Direction=false, State, SEG_SEQ, SEG_LEN) ->
    sequence_no_in_window(SEG_SEQ, State#state.responder_RCV_NXT,
			  calculate_window(not(Direction), State), SEG_LEN).

calculate_window(true = _Direction, State) ->
    calculate_window(State#state.initiator_RCV_WND, State#state.initiator_RCV_WND_SCALE, State#state.responder_RCV_WND_SCALE);

calculate_window(false= _Direction, State) ->
    calculate_window(State#state.responder_RCV_WND, State#state.responder_RCV_WND_SCALE, State#state.initiator_RCV_WND_SCALE).

calculate_window(WND, undefined, undefined) ->
    WND;

calculate_window(WND, _WND_SCALE, undefined) ->
    WND;

calculate_window(WND, undefined, _PEER_SIDE_WND_SCALE) ->
    WND;

calculate_window(WND, WND_SCALE, _PEER_SIDE_WND_SCALE) when WND_SCALE =< 14->
    WND bsl WND_SCALE;

calculate_window(WND, _WND_SCALE, _PEER_SIDE_WND_SCALE)->
    WND bsl 14.

storeState_RCV_NXT(Direction=true,     State,  SEG_SEQ, true) ->
    State#state{initiator_RCV_NXT = forward_sequence_no(modulo32bit(SEG_SEQ + 1), State#state.initiator_RCV_NXT, calculate_window(Direction, State))};

storeState_RCV_NXT(Direction=true,     State,  SEG_SEQ, false) ->
    State#state{initiator_RCV_NXT = forward_sequence_no(modulo32bit(SEG_SEQ + 0), State#state.initiator_RCV_NXT, calculate_window(Direction, State))};

storeState_RCV_NXT(Direction=false,     State,  SEG_SEQ, true) ->
    State#state{responder_RCV_NXT = forward_sequence_no(modulo32bit(SEG_SEQ + 1), State#state.responder_RCV_NXT, calculate_window(Direction, State))};

storeState_RCV_NXT(Direction=false,     State,  SEG_SEQ, false) ->
    State#state{responder_RCV_NXT = forward_sequence_no(modulo32bit(SEG_SEQ + 0), State#state.responder_RCV_NXT, calculate_window(Direction, State))}.

storeState_RCV_NXT(Direction=true, #state{initiator_RCV_NXT = RCV_NXT} = State, SEG_SEQ, SEG_LEN, true = _Syn_or_Fin)
  when (RCV_NXT == SEG_SEQ)->
    %%error_logger:info_msg("Ports: ~p <-> ~p RCV_NXT:~p  matches SEG_SEQ:~p~n"), [State#state.initiator_port, State#state.responder_port, RCV_NXT, SEG_SEQ]),
    State#state{initiator_RCV_NXT = forward_sequence_no(modulo32bit(SEG_SEQ+SEG_LEN +1), State#state.initiator_RCV_NXT, calculate_window(Direction, State))};

storeState_RCV_NXT(Direction=true, #state{initiator_RCV_NXT = RCV_NXT} = State, SEG_SEQ, SEG_LEN, false = _Syn_or_Fin)
  when (RCV_NXT == SEG_SEQ)->
    %%error_logger:info_msg("Ports: ~p <-> ~p RCV_NXT:~p  matches SEG_SEQ:~p~n", [State#state.initiator_port, State#state.responder_port,RCV_NXT, SEG_SEQ]),
    State#state{initiator_RCV_NXT = forward_sequence_no(modulo32bit(SEG_SEQ+SEG_LEN + 0), State#state.initiator_RCV_NXT, calculate_window(Direction, State))};

storeState_RCV_NXT(Direction=false, #state{responder_RCV_NXT = RCV_NXT} = State, SEG_SEQ, SEG_LEN, true = _Syn_or_Fin)
  when (RCV_NXT == SEG_SEQ)->
    %%error_logger:info_msg("Ports: ~p <-> ~p RCV_NXT:~p  matches SEG_SEQ:~p~n", [State#state.responder_port, State#state.initiator_port,RCV_NXT, SEG_SEQ]),
    State#state{responder_RCV_NXT = forward_sequence_no(modulo32bit(SEG_SEQ+SEG_LEN +1), State#state.responder_RCV_NXT, calculate_window(Direction, State))};

storeState_RCV_NXT(Direction=false,  #state{responder_RCV_NXT = RCV_NXT} = State, SEG_SEQ, SEG_LEN, false = _Syn_or_Fin)
  when (RCV_NXT == SEG_SEQ)->
    %%error_logger:info_msg("Ports: ~p <-> ~p RCV_NXT:~p  matches SEG_SEQ:~p~n", [State#state.responder_port, State#state.initiator_port,RCV_NXT, SEG_SEQ]),
    State#state{responder_RCV_NXT = forward_sequence_no(modulo32bit(SEG_SEQ+SEG_LEN +0), State#state.responder_RCV_NXT, calculate_window(Direction, State))};

storeState_RCV_NXT(true,  #state{initiator_RCV_NXT = _RCV_NXT} = State, _SEG_SEQ, _SEG_LEN,  _Syn_or_Fin) ->
    %%error_logger:info_msg("Ports: ~p <-> ~p RCV_NXT:~p does not match SEG_SEQ:~p~n", [State#state.initiator_port, State#state.responder_port, _RCV_NXT, _SEG_SEQ]),
    State;

storeState_RCV_NXT(false,  #state{responder_RCV_NXT = _RCV_NXT} = State, _SEG_SEQ, _SEG_LEN,  _Syn_or_Fin) ->
    %%error_logger:info_msg("Ports: ~p <-> ~p RCV_NXT:~p does not match SEG_SEQ:~p~n", [State#state.responder_port, State#state.initiator_port,_RCV_NXT, _SEG_SEQ]),
    State.

storeState_SND_UNA(_, State, _SEG_ACK, false) ->
    State;

storeState_SND_UNA(true = Direction, State, SEG_ACK, true) ->
    case test_ack_valid(Direction, State, SEG_ACK) of
	valid_ack ->
	    %%error_logger:info_msg("Valid Ack!! Forwarding SND_UNA from:  ~p to: ~p~n",[State#state.initiator_SND_UNA, add_modulo_32bit(SEG_ACK,0)]),
	    State#state{initiator_SND_UNA = add_modulo_32bit(SEG_ACK,0)};
	repetition_ack ->
	    %%error_logger:info_msg("Information: Repetition Ack:~p received~n",[SEG_ACK]),
	    State;
	invalid_ack ->
            SND_UNA = State#state.initiator_SND_UNA,
            SND_WND = calculate_window(Direction, State),
	    %%error_logger:error_msg("Error: ~ninvalid Ack: ~p for SND_UNA: ~p SND_WND: ~p and SND_UNA+SND_WND: ~p received~n",[SEG_ACK, SND_UNA, SND_WND, SND_UNA+SND_WND]),
	    State
    end;

storeState_SND_UNA(false = Direction, State, SEG_ACK, true) ->
    case test_ack_valid(Direction, State, SEG_ACK) of
	valid_ack ->
	    %%error_logger:info_msg("Valid Ack!! Forwarding SND_UNA from:  ~p to: ~p~n",[State#state.responder_SND_UNA, add_modulo_32bit(SEG_ACK,0)]),
	    State#state{responder_SND_UNA = add_modulo_32bit(SEG_ACK,0)};
	repetition_ack ->
	    %%error_logger:info_msg("Information: Repetition Ack:~p received~n",[SEG_ACK]),
	    State;
	invalid_ack ->
            SND_UNA = State#state.responder_SND_UNA,
            SND_WND = calculate_window(Direction, State),
	    %%error_logger:error_msg("Error: ~ninvalid Ack: ~p for SND_UNA: ~p SND_WND: ~p and SND_UNA+SND_WND: ~p received~n",[SEG_ACK, SND_UNA, SND_WND, SND_UNA+SND_WND]),
	    State
    end.


storeState_SND_WND(true = _Direction, State, SEG_WND) ->
    State#state{initiator_RCV_WND = SEG_WND};

storeState_SND_WND(false = _Direction, State, SEG_WND) ->
    State#state{responder_RCV_WND = SEG_WND}.

storeState_Payload(_Direction=true, State, _SEG_SEQ, 0 =_PayloadLength, <<>> = _Payload) ->
    State; %% ignore zero payload length packages

storeState_Payload(_Direction=false, State, _SEG_SEQ, 0 =_PayloadLength, <<>> = _Payload) ->
    State; %% ignore zero payload length packages

storeState_Payload(_Direction=true, State, SEG_SEQ, PayloadLength, Payload) ->
    SmallerOrEqualFun = fun({A,_, _},{B,_, _}) -> A =< B end,
    StateNew = State#state{initiator_payload_store = lists:usort(SmallerOrEqualFun, [{SEG_SEQ, PayloadLength, Payload}|State#state.initiator_payload_store])},
    %%error_logger:info_msg("PayloadStore Direction ~p contains now ~p packages~n",[_Direction, length(StateNew#state.initiator_payload_store)]),
    StateNew;

storeState_Payload(_Direction=false, State, SEG_SEQ, PayloadLength, Payload) ->
    SmallerOrEqualFun = fun({A,_, _},{B,_, _}) -> A =< B end,
    StateNew = State#state{responder_payload_store = lists:usort(SmallerOrEqualFun, [{SEG_SEQ, PayloadLength, Payload}|State#state.responder_payload_store])},
    %%error_logger:info_msg("PayloadStore Direction: ~p contains now ~p packages~n",[_Direction, length(StateNew#state.responder_payload_store)]),
    StateNew.

storeState_SND_WND_SCALE(true, State, ShiftCount) ->
    State#state{initiator_RCV_WND_SCALE = ShiftCount};

storeState_SND_WND_SCALE(false, State, ShiftCount) ->
    State#state{responder_RCV_WND_SCALE = ShiftCount}.


copy_state_to_close_initiator_close_responder(true, State) ->
    State#state{
      close_initiator_address       = State#state.initiator_address,
      close_initiator_port          = State#state.initiator_port,
      close_responder_address       = State#state.responder_address,
      close_responder_port          = State#state.responder_port};

copy_state_to_close_initiator_close_responder(false, State) ->
    State#state{
      close_initiator_address       = State#state.responder_address,
      close_initiator_port          = State#state.responder_port,
      close_responder_address       = State#state.initiator_address,
      close_responder_port          = State#state.initiator_port}.

log_initiator_responder(_StateName, _SEG_SEQ, _SEG_ACK, _SEG_WND, _State) ->
    %%error_logger:info_msg("State: ~p, SEG_SEQ: ~w, SEG_ACK: ~w, SEG_WND: ~w~n", [_StateName, _SEG_SEQ, _SEG_ACK, _SEG_WND]),
    %%error_logger:warning_msg("i_address: ~p, i_port : ~w, i_RCV_WND ~w, i_SND_UNA: ~w, i_RCV_NXT:~w~n", [_State#state.initiator_address, _State#state.initiator_port, _State#state.initiator_RCV_WND, _State#state.initiator_SND_UNA, _State#state.initiator_RCV_NXT]),
    %%error_logger:info_msg("r_address: ~p, r_port : ~w, r_RCV_WND ~w, r_SND_UNA: ~w, r_RCV_NXT: ~w~n", [_State#state.responder_address, _State#state.responder_port, _State#state.responder_RCV_WND, 	_State#state.responder_SND_UNA, _State#state.responder_RCV_NXT]),
    true.


forward_payload(ServerPids, Source, Destination, Payload) ->
    forward_payload(ServerPids, Source, Destination, Payload, 0, 0).

forward_payload([ServerPid|ServerPids], {Source_address, Source_port} = _Source,{Destination_address, Destination_port} = _Destination, Payload, Sent_packets, Sent_bytes) ->
    %%error_logger:info_msg("Sending data: ServerPid: ~p, Source: ~p:~p, Destination: ~p:~p, PayloadLength ~p~n", [ServerPid, Source_address, Source_port, Destination_address, Destination_port, byte_size(Payload)]),
    Sent_bytesNew = Sent_bytes +byte_size(Payload), 
    ok= gen_server:call(ServerPid, {payload_section, Source_address, Source_port, Destination_address, Destination_port, Payload}, infinity),
    Sent_packetsNew = Sent_packets+1, 
    forward_payload(ServerPids, {Source_address, Source_port}, {Destination_address, Destination_port}, Payload, Sent_packetsNew, Sent_bytesNew);

forward_payload([], _Source, _Destination, _Payload, Sent_packets, Sent_bytes) ->
    {ok, Sent_packets, Sent_bytes}.

%% Here Direction is always the opposite side, as Ack forwards the packages of the peer side
forward_stream_ack_payload_store(Direction=false, Fin, Source, Destination, #state{initiator_ack_payload_store = Payload_store} = State) when byte_size(Payload_store) >= 1500->
    <<Payload_forward:1500/binary-unit:8, Payload_rest/binary>> = Payload_store,
    {ok, Sent_packets, Sent_bytes} = forward_payload(State#state.child_worker_list,  Source, Destination, Payload_forward),
    StateNew = State#state{initiator_ack_payload_store = Payload_rest, sent_packets = State#state.sent_packets + Sent_packets, sent_bytes = State#state.sent_bytes + Sent_bytes},
    forward_stream_ack_payload_store(Direction, Fin, Source, Destination, StateNew);

forward_stream_ack_payload_store(Direction=true, Fin, Source, Destination, #state{responder_ack_payload_store = Payload_store} = State) when byte_size(Payload_store) >= 1500->
    <<Payload_forward:1500/binary-unit:8, Payload_rest/binary>> = Payload_store,
    {ok, Sent_packets, Sent_bytes} = forward_payload(State#state.child_worker_list,  Source, Destination, Payload_forward),
    StateNew = State#state{responder_ack_payload_store = Payload_rest, sent_packets = State#state.sent_packets + Sent_packets, sent_bytes = State#state.sent_bytes + Sent_bytes},
    forward_stream_ack_payload_store(Direction, Fin, Source, Destination, StateNew);

forward_stream_ack_payload_store(_Direction=false, true = _Fin, Source, Destination, #state{initiator_ack_payload_store = Payload_store} = State)->
    {ok, Sent_packets, Sent_bytes} = forward_payload(State#state.child_worker_list, Source, Destination, Payload_store),
    StateNew = State#state{initiator_ack_payload_store = <<>>, sent_packets = State#state.sent_packets + Sent_packets, sent_bytes = State#state.sent_bytes + Sent_bytes},
    StateNew;

forward_stream_ack_payload_store(_Direction=true, true = _Fin, Source, Destination, #state{initiator_ack_payload_store = Payload_store} = State)->
    {ok, Sent_packets, Sent_bytes} = forward_payload(State#state.child_worker_list, Source, Destination, Payload_store),
    StateNew = State#state{responder_ack_payload_store = <<>>, sent_packets = State#state.sent_packets + Sent_packets, sent_bytes = State#state.sent_bytes + Sent_bytes},
    StateNew;

forward_stream_ack_payload_store(_Direction=true, false = _Fin, _Source, _Destination, State) ->
    State;

forward_stream_ack_payload_store(_Direction=false, false = _Fin, _Source, _Destination, State) ->
    State.


checkPayloadReceptionBuffer(_Direction=true, false = _Ack, _SEG_ACK, _Syn_or_Fin, #state{} = State) ->
    %%error_logger:info_msg("Received: Package with Ack = false in Direction ~p~n", [_Direction]),
    State;

checkPayloadReceptionBuffer(_Direction=false, false = _Ack, _SEG_ACK, _Syn_or_Fin, #state{} = State) ->
    %%error_logger:info_msg("Received: Package with Ack = false in Direction ~p~n", [_Direction]),
    State;

checkPayloadReceptionBuffer(_Direction=true, _Ack, _SEG_ACK, _Syn_or_Fin, #state{initiator_payload_store = []} = State) ->
    %%error_logger:info_msg("Check payload_store: Payloadstore in Direction ~p is empty~n", [_Direction]),
    State;

checkPayloadReceptionBuffer(_Direction=false, _Ack, _SEG_ACK, _Syn_or_Fin, #state{responder_payload_store = []} = State) ->
    %%error_logger:info_msg("Check payload_store: Payloadstore in Direction ~p is empty~n", [_Direction]),
    State;

checkPayloadReceptionBuffer(Direction=true, Ack, SEG_ACK, Syn_or_Fin, #state{initiator_RCV_NXT = RCV_NXT, initiator_payload_store = [{SEG_SEQ, PayloadLength, Payload}|PayloadFrames]} = State) ->
    RCV_NXT32 = modulo32bit(RCV_NXT),
    SEG_SEQ32 = modulo32bit(SEG_SEQ),
    SEG_ACK32 = modulo32bit(SEG_ACK),
    %% test SEG_SEQ32 =< RCV_NXT32 =< SEG_ACK
    case smaller_or_equal(SEG_SEQ32, RCV_NXT32) of
	true ->
	    case smaller_or_equal(RCV_NXT32, SEG_ACK32) of
		true ->
		    case (Ack == true) of
			true ->
			    %%error_logger:info_msg("Check payload_store: Payloadstore in Direction ~p has first payload with:~p bytes~n", [Direction, PayloadLength]),
			    Delta_overlap_ignore = add_modulo_32bit(RCV_NXT32, -SEG_SEQ32),
			    case Delta_overlap_ignore =< PayloadLength of
				true ->
				    Ack_payload_store = State#state.initiator_ack_payload_store,
				    <<_Ignore:Delta_overlap_ignore/binary, Payload_non_duplicate/binary>> = <<Payload/binary>>,
				    StateNew1 = State#state{initiator_ack_payload_store = <<Ack_payload_store/binary, Payload_non_duplicate/binary>>},
				    StateNew2 = storeState_RCV_NXT(Direction, StateNew1, SEG_SEQ, PayloadLength-Delta_overlap_ignore, Syn_or_Fin),
				    StateNew  = StateNew2#state{initiator_payload_store = PayloadFrames},
				    checkPayloadReceptionBuffer(Direction, Ack, SEG_ACK32, Syn_or_Fin, StateNew);
				false ->
				    error_logger:error_msg("Check payload failed as no new data available!!!!Direction: ~p, SEG_SEQ: ~p, RCV_NXT:~p, PayloadLength: ~p~n",[Direction, SEG_SEQ, RCV_NXT, PayloadLength]),
				    State#state{initiator_payload_store = PayloadFrames}
			    end;
			false ->
		            %%error_logger:warning_msg("Information: Package with Ack == false received~n"),
			    State % Ack == false
		    end;
		false ->
		    %% overlapping received data and acknowledgement
		    State
	    end;
	false ->
            %%error_logger:error_msg("Warning !!!!, SEG_SEQ > RCV_NXT, Direction: ~p, SEG_SEQ: ~p, RCV_NXT:~p~n",[Direction, SEG_SEQ, RCV_NXT]),
	    State
    end;

checkPayloadReceptionBuffer(Direction=false, Ack, SEG_ACK, Syn_or_Fin, #state{responder_RCV_NXT = RCV_NXT, responder_payload_store = [{SEG_SEQ, PayloadLength, Payload}|PayloadFrames]} = State) ->
    Direction=false,
    RCV_NXT32 = modulo32bit(RCV_NXT),
    SEG_SEQ32 = modulo32bit(SEG_SEQ),
    SEG_ACK32 = modulo32bit(SEG_ACK),
    %% test SEG_SEQ32 =< RCV_NXT32 =< SEG_ACK
    case smaller_or_equal(SEG_SEQ32, RCV_NXT32) of
	true ->
	    case smaller_or_equal(RCV_NXT32, SEG_ACK32) of
		true ->
		    case (Ack == true) of
			true ->
			    %%error_logger:info_msg("Check payload_store: Payloadstore in Direction ~p has first payload with:~p bytes~n", [Direction, PayloadLength]),
			    Delta_overlap_ignore = add_modulo_32bit(RCV_NXT32, -SEG_SEQ32),
			    case Delta_overlap_ignore =< PayloadLength of
				true ->
				    Ack_payload_store = State#state.responder_ack_payload_store,
				    <<_Ignore:Delta_overlap_ignore/binary, Payload_non_duplicate/binary>> = <<Payload/binary>>,
				    StateNew1 = State#state{responder_ack_payload_store = <<Ack_payload_store/binary, Payload_non_duplicate/binary>>},
				    StateNew2 = storeState_RCV_NXT(Direction, StateNew1, SEG_SEQ, PayloadLength-Delta_overlap_ignore, Syn_or_Fin),
				    StateNew  = StateNew2#state{responder_payload_store = PayloadFrames},
				    checkPayloadReceptionBuffer(Direction, Ack, SEG_ACK32, Syn_or_Fin, StateNew);
				false ->
				    error_logger:error_msg("Check payload failed as no new data available!!!!Direction: ~p, SEG_SEQ: ~p, RCV_NXT:~p, PayloadLength: ~p~n",[Direction, SEG_SEQ, RCV_NXT, PayloadLength]),
				    State#state{responder_payload_store = PayloadFrames}
			    end;
			false ->
			    %%error_logger:info_msg("Information: Package with Ack == false received~n"),
			    State % Ack == false
		    end;
		false ->
		    % overlapping received data and acknowledgement
		    State
	    end;
	false ->
	    %%error_logger:error_msg("Warning !!!!, SEG_SEQ > RCV_NXT, Direction: ~p, SEG_SEQ: ~p, RCV_NXT:~p~n",[Direction, SEG_SEQ, RCV_NXT]),
	    State
    end.


storeState_SACK_PERMITTED(_Direction=true, State) ->
    State#state{initiator_sack_permitted = true};

storeState_SACK_PERMITTED(_Direction=false, State) ->
    State#state{responder_sack_permitted = true}.

%% does_connection_support_SACK(State) ->
%% 	does_connection_support_SACK(State#state.initiator_sack_permitted, State#state.responder_sack_permitted).

%% does_connection_support_SACK(undefined, undefined) ->
%%         false;

%% does_connection_support_SACK(true, undefined) ->
%%         false;

%% does_connection_support_SACK(undefined, true) ->
%%         false;

%% does_connection_support_SACK(true, true) ->
%%         true.

determine_Direction({{_Source_address, _Source_port} = Source,{_Destination_address, _Destination_port} = Destination}, State) ->
    Initiator_address = State#state.initiator_address,
    Initiator_port = State#state.initiator_port,
    Responder_address = State#state.responder_address,
    Responder_port = State#state.responder_port,
    case {Source, Destination} of
	{{Initiator_address, Initiator_port}, {Responder_address, Responder_port}} ->
	    true;
	{{Responder_address, Responder_port}, {Initiator_address, Initiator_port}} ->
	    false
    end.

stack_new(MaxStackSize) ->
    {queue:new(),MaxStackSize}.

stack_element(Element, {Stack, MaxStackSize}) ->
    StackSize = queue:len(Stack),
    if
        StackSize < MaxStackSize ->
	    StackNew = queue:in(Element,Stack);
        true ->
	    StackNew1 = queue:in(Element,Stack),
	    {_StackDump, StackNew} = queue:split(1, StackNew1)
	    %%io:format("StackNew1: ~p, StackDump: ~p ~n", [StackNew1, _StackDump])
    end,
    {StackNew, MaxStackSize}.


stack_member(Element, {Stack, _MaxStackSize}) ->
    lists:member(Element, queue:to_list(Stack)).

