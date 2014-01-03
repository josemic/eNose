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

-include_lib("pkt/include/pkt.hrl").
-include("debug_macro.hrl").
-include("decoded.hrl").

%% API
-export([compare32/2, start_link/3, forward_sequence_no/3, modulo32bit/1, send_packet/2, stop/1, smaller32/2, smaller_or_equal32/2]).

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
%%-define(GEN_FSM_OPTS, {debug, [trace, {log_to_file, "log/stream/trace_worker_"++Name_s++".log"}]}).
-define(GEN_FSM_OPTS, {debug, [{log_to_file, "log/stream/trace_worker_"++Name_s++".log"}]}).
%%-define(GEN_FSM_OPTS, {debug, [{install,{Dbg_fun,state}}]}).
%%-define(GEN_FSM_OPTS, {debug, [{install,{Dbg_fun,state}}, {log_to_file, "log/stream/trace_worker_"++Name_s++".log"}]}).
%%-define(GEN_FSM_OPTS, {debug, [trace]}).
-else.
-define(GEN_FSM_OPTS, []).
-endif.

-define(DEBUG_BUFFER, true).
-ifdef(DEBUG_BUFFER).
-define(DEBUG_LOG(Term, Direction, IP, TCP, Decoded, State), State#state{stack_trace_path=[{Term, Direction, (TCP#tcp.ack =:= 1), (TCP#tcp.syn =:= 1), TCP#tcp.fin, TCP#tcp.rst, TCP#tcp.seqno, TCP#tcp.ackno, TCP#tcp.win, Decoded#decoded.payload_size}|State#state.stack_trace_path]}). 
-else.
-define(DEBUG_LOG(_Term, _Direction, _IP, _TCP, _Decoded, State), State).
-endif.

-define(current_function_name(),
	element(2, element(2, process_info(self(), current_function)))).

-record(state, {
	  sent_packets::integer(),
	  sent_bytes::integer(),
	  child_worker_list :: [pid()],
	  instance::integer(),
	  syn_ack_received::boolean(),
	  fin_ack_received::boolean(),
          overlapping_payload_strategy::atom(), % first_wins or last_wins
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
	  close_initiator::atom(),
          close_responder::atom(),
          initiator_payload_store::queue(),
          responder_payload_store::queue(),
          initiator_ack_payload_store::binary(),
          responder_ack_payload_store::binary(),
          initiator_sack_permitted::binary(),
	  responder_sack_permitted::binary(),
          stack_trace_path::[atom()],
          initiator_syn_seg_seq_stack::[integer()], %% stack!!!
          initiator_last_SEG_SEQ::integer(),
          responder_last_SEG_SEQ::integer(),
          initiator_retransmission_index::integer(),
          responder_retransmission_index::integer(),
          initiator_sack_store::[tuple()],
          responder_sack_store::[tuple()],
          responder, % record connection
          initiator  % record connection
	 }).

-record(connection, {
	  address::[tuple],
          port::[tuple],
          rcv_nxt::integer(),
          snd_una::integer(),
          rcv_wnd::integer(),
          rcv_wnd_scale::integer(),
          payload_store::queue(),
          ack_payload_store::binary(),
          sack_permitted::binary(),
          syn_seg_seq_stack::[integer()], %% stack!!!, initiator only
          last_SEG_SEQ::integer(),
          retransmission_index::integer(),
          sack_store::[tuple()]
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
start_link(Instance, {Direction=initiator, IP, TCP, Decoded}, ChildWorkerList) when Decoded#decoded.payload_size ==0 ->
    Instance_s = integer_to_list(Instance),
    Ref_s = erlang:ref_to_list(make_ref()),
    Name_s = ?MODULE_STRING ++ "_" ++ Instance_s ++ "_" ++ Ref_s ++ "_" ++ lists:flatten(io_lib:format("~p",[now()])) ++ "_" ++
	lists:flatten(io_lib:format("~p", [Decoded#decoded.source_address])) ++ ":" ++
	lists:flatten(io_lib:format("~p", [TCP#tcp.sport])) ++ "_" ++
	lists:flatten(io_lib:format("~p", [Decoded#decoded.destination_address])) ++ ":" ++
	lists:flatten(io_lib:format("~p", [TCP#tcp.dport])),
    Name = list_to_atom (Name_s),
    gen_fsm:start_link({local,Name},?MODULE,[Instance, {Direction=initiator, IP, TCP, Decoded}, ChildWorkerList],[?GEN_FSM_OPTS]).

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

init([Instance,{Direction=initiator, IP, TCP, Decoded}, ChildWorkerList]) ->
    State = #state{
               sent_packets =0,
               sent_bytes = 0,
	       instance = Instance,
               overlapping_payload_strategy = first_wins,
	       close_initiator = undefined,
               close_responder = undefined,
	       child_worker_list = ChildWorkerList,
	       syn_ack_received = false,
               fin_ack_received = false,
               initiator_payload_store = queue:new(),
               responder_payload_store = queue:new(),
               initiator_ack_payload_store = <<>>,
               responder_ack_payload_store = <<>>,
               initiator_sack_permitted=undefined,
               responder_sack_permitted=undefined,
               initiator_syn_seg_seq_stack=stack_new(?MaxNumberOfSynSegSeqOnStack),
               initiator_last_SEG_SEQ = undefined,
               responder_last_SEG_SEQ = undefined,
               initiator_retransmission_index = 0,
               responder_retransmission_index = 0,
               initiator_sack_store=[],
               responder_sack_store=[]        
	      },
    {ok, _Timeout, StateNew} = handle_initial_syn_or_syn_after_reset(?current_function_name(), New_state_name = state_syn_sent, {Direction, IP, TCP, Decoded}, State), 
    {ok, New_state_name, StateNew}.

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

state_listen( % this state ocurrs only after reset
  {Direction = initiator, 
   IP, 
   #tcp{ack=0, syn=1, fin=0, rst=0}=TCP, 
   #decoded{payload_size = 0} = Decoded
  }, State) ->
    {ok, StateNew} = handle_initial_syn_or_syn_after_reset(?current_function_name(), New_state_name = state_syn_sent, {Direction, IP, TCP, Decoded}, State), 
    {ok, New_state_name, StateNew};

state_listen(
  {Direction,  %% unclear, whether that applies ony for initiator. To be checked. 
   IP, 
   #tcp{rst=1}=TCP, 
   Decoded
  }, State) -> 
    %% Rst in state_listen, see RFC 793, p. 37
    %% Rst should be ignored // RFC 793, p65
    {ok, Timeout, StateNew}= handle_ignore(NextStateName = ?current_function_name(), {Direction, IP, TCP, Decoded}, State),
    {next_state, NextStateName, StateNew, Timeout};

state_listen(
  {Direction, 
   IP, 
   #tcp{ack=1}=TCP, 
   Decoded
  }, State) -> 
    StateNew0 = ?DEBUG_LOG({?current_function_name()}, Direction, IP, TCP, Decoded, State),
    StateNew = StateNew0,
    %% ignore all Ack packages // RCF 793 p. 65
    {ok, Timeout, StateNew}= handle_ignore(NextStateName = ?current_function_name(), {Direction, IP, TCP, Decoded}, State),
    {next_state, NextStateName, StateNew, Timeout};

state_listen(timeout, State) ->
    %%error_logger:warning_msg("Closing Instance: ~p~n in state listen", [State#state.instance]),
    {stop, shutdown, State}.

state_syn_sent(
  {Direction = responder, 
   IP, 
   #tcp{ack=0, syn=1, fin=0, rst=0}=TCP, 
   #decoded{payload_size = 0} = Decoded
  }, State) when
      State#state.syn_ack_received == true -> % !!!!!!!! Ack received before->
    {ok, NextStateName, Timeout, StateNew }= handle_syn_ack_response_syn(?current_function_name(), state_syn_sent, {Direction, IP, TCP, Decoded}, State),
    {next_state, NextStateName, StateNew, Timeout}; 

state_syn_sent(
  {Direction = responder, 
   IP, 
   #tcp{ack=1, syn=0, fin=0, rst=0}=TCP, 
   Decoded
  }, State) ->
    {ok, NextStateName, Timeout, StateNew }= handle_syn_response_ack(?current_function_name(), state_syn_sent, {Direction, IP, TCP, Decoded}, State),
    {next_state, NextStateName, StateNew, Timeout};

state_syn_sent(
  {Direction = initiator, 
   IP, 
   #tcp{ack=0, syn=1, fin=0, rst=0}=TCP, 
   #decoded{payload_size = 0} = Decoded
  }, State) ->

    {ok, NextStateName, Timeout, StateNew }= handle_syn_repetition(?current_function_name(), {Direction, IP, TCP, Decoded}, State),
    {next_state, NextStateName, StateNew, Timeout};

state_syn_sent(
  {Direction = responder, 
   IP, 
   #tcp{ack=1, syn=1, fin=0, rst=0}=TCP, % Syn-Ack
   #decoded{payload_size = 0} = Decoded
  }, State) -> 
    {ok, NextStateName, Timeout, StateNew }= handle_syn_response_synack(?current_function_name(), state_syn_syn_ack_sent, {Direction, IP, TCP, Decoded}, State),
    {next_state, NextStateName, StateNew, Timeout};

state_syn_sent(
  {Direction = initiator, 
   IP, 
   #tcp{syn=0, fin=1, rst=0}=TCP, 
   #decoded{payload_size = 0} = Decoded
  }, State) -> 
    {ok, NextStateName, Timeout, StateNew }= handle_initial_fin(?current_function_name(), state_fin_wait_1, {Direction, IP, TCP, Decoded}, State),
    {next_state, NextStateName, StateNew, Timeout};

state_syn_sent(
  {Direction, 
   IP, 
   #tcp{rst=1}=TCP, 
   Decoded
  }, State) -> 
    {ok, NextStateName, Timeout, StateNew}= handle_reset(?current_function_name(), state_listen, {Direction, IP, TCP, Decoded}, State),
    {next_state, NextStateName, StateNew, Timeout}.

state_syn_syn_ack_sent(
  {Direction = initiator, 
   IP, 
   #tcp{ack=1, syn=0, fin=0, rst=0}=TCP, 
   Decoded
  }, State) ->
    {ok, NextStateName, Timeout, StateNew }= handle_payload(?current_function_name(), state_established, {Direction, IP, TCP, Decoded}, State),
    {next_state, NextStateName, StateNew, Timeout};

state_syn_syn_ack_sent(  
  {Direction = responder, 
   IP, 
   #tcp{ack=1, syn=0, fin=0, rst=0}=TCP, % Ack retransmission
   #decoded{payload_size = 0} = Decoded
  }, State) -> 
    {ok, Timeout, StateNew}= handle_retransmission(NextStateName = ?current_function_name(), {Direction, IP, TCP, Decoded}, State),
    {next_state, NextStateName, StateNew, Timeout};

state_syn_syn_ack_sent(
  {Direction = initiator, 
   IP, 
   #tcp{fin=1, rst=0}=TCP, 
   #decoded{payload_size = 0} = Decoded
  }, State) -> 
    {ok, NextStateName, Timeout, StateNew }= handle_initial_fin(?current_function_name(), state_fin_wait_1, {Direction, IP, TCP, Decoded}, State),
    {next_state, NextStateName, StateNew, Timeout};

state_syn_syn_ack_sent(
  {Direction = responder, 
   IP, 
   #tcp{fin=1, rst=0}=TCP, 
   #decoded{payload_size = 0} = Decoded
  }, State) -> 
    {ok, NextStateName, Timeout, StateNew } = handle_initial_fin(?current_function_name(), state_fin_wait_1, {Direction, IP, TCP, Decoded}, State),
    {next_state, NextStateName, StateNew, Timeout};


state_syn_syn_ack_sent(
  {Direction, % Direction: initiator or responder
   IP, 
   #tcp{rst=1}=TCP, % Rst
   #decoded{payload_size = 0} = Decoded
  }, State) -> 
    {ok, NextStateName, Timeout, StateNew}= handle_reset(?current_function_name(), state_listen, {Direction, IP, TCP, Decoded}, State),
    {next_state, NextStateName, StateNew, Timeout}.

state_syn_received( % Ack
  {Direction = initiator, 
   IP, 
   #tcp{ack=1, syn=0, fin=0, rst=0}=TCP, 
   #decoded{payload_size = 0} = Decoded
  }, State) -> 
    {ok, NextStateName, Timeout, StateNew }= handle_payload(?current_function_name(), state_established, {Direction, IP, TCP, Decoded}, State),
    {next_state, NextStateName, StateNew, Timeout};

state_syn_received(  {Direction,  % Direction: initiator or responder 
		      IP, 
		      #tcp{fin=1, rst=0}=TCP, % Fin / Fin-Ack
		      Decoded
		     }, State) -> 
    {ok, NextStateName, Timeout, StateNew }= handle_initial_fin(?current_function_name(), state_fin_wait_1, {Direction, IP, TCP, Decoded}, State),
    {next_state, NextStateName, StateNew, Timeout};


state_syn_received( % Rst as connection initiator received. 
  {Direction = initiator, 
   IP, 
   #tcp{rst=1}=TCP, 
   Decoded
  }, State) -> 
    {ok, NextStateName, Timeout, StateNew}= handle_reset(?current_function_name(), state_time_wait, {Direction, IP, TCP, Decoded}, State),
    {next_state, NextStateName, StateNew, Timeout};

state_syn_received( % Rst as connection responder received, see RFC 793, p. 37. Go back to listen.
  {Direction = responder, 
   IP, 
   #tcp{rst=1}=TCP, 
   #decoded{payload_size = 0} = Decoded
  }, State) -> 
    {ok, NextStateName, Timeout, StateNew}= handle_reset(?current_function_name(), state_listen, {Direction, IP, TCP, Decoded}, State),
    {next_state, NextStateName, StateNew, Timeout}.

state_established( % payload, Note: if ack == 0, seqno should be 0
  {Direction, % initiator or responder  
   IP, 
   #tcp{syn=0, fin=0, rst=0}=TCP, 
   Decoded
  }, State) ->
    {ok, NextStateName, Timeout, StateNew }= handle_payload(?current_function_name(), state_established, {Direction, IP, TCP, Decoded}, State),
    {next_state, NextStateName, StateNew, Timeout};

state_established( % Syn-Ack retransmission
  {Direction, % initiator or responder
   IP, 
   #tcp{ack=1, syn=1, fin=0, rst=0}=TCP, 
   #decoded{payload_size = 0} = Decoded
  }, State) -> 
    {ok, Timeout, StateNew}= handle_retransmission(NextStateName = ?current_function_name(), {Direction, IP, TCP, Decoded}, State),
    {next_state, NextStateName, StateNew, Timeout};

state_established( % Fin / Fin-Ack
  {Direction, % initiator or responder
   IP, 
   #tcp{ syn=0, fin=1, rst=0}=TCP, 
   Decoded
  }, State) ->
    {ok, NextStateName, Timeout, StateNew }= handle_initial_fin(?current_function_name(), state_fin_wait_1, {Direction, IP, TCP, Decoded}, State),
    {next_state, NextStateName, StateNew, Timeout};

state_established(
  {Direction, % initiator or responder
   IP, 
   #tcp{rst=1}=TCP, 
   Decoded
  }, State) ->
    {ok, NextStateName, Timeout, StateNew}= handle_reset(?current_function_name(), state_time_wait, {Direction, IP, TCP, Decoded}, State),
    {next_state, NextStateName, StateNew, Timeout}.

state_fin_wait_1( % Fin-Ack
  {Direction, % close_responder
   IP, 
   #tcp{ack=1, syn=0, fin=1, rst=0}=TCP, 
   Decoded
  }, State) when 
      Direction == State#state.close_responder -> 
    {ok, NextStateName, Timeout, StateNew }= handle_payload(?current_function_name(), state_time_wait, {Direction, IP, TCP, Decoded}, State),
    {next_state, NextStateName, StateNew, Timeout};

state_fin_wait_1( % Fin-Ack retransmission
  {Direction, % close_initiator 
   IP, 
   #tcp{ack=1, syn=0, fin=1, rst=0}=TCP, 
   Decoded
  }, State) when 
      Direction == State#state.close_initiator-> 
    {ok, Timeout, StateNew}= handle_retransmission(NextStateName = ?current_function_name(), {Direction, IP, TCP, Decoded}, State),
    {next_state, NextStateName, StateNew, Timeout};

state_fin_wait_1( % Ack
  {Direction,  % close_responder
   IP, 
   #tcp{ack=1, syn=0, fin=0, rst=0}=TCP, 
   Decoded
  }, State) when 
      Direction == State#state.close_responder -> 
    {ok, NextStateName, Timeout, StateNew }= handle_payload(?current_function_name(), state_fin_wait_1, {Direction, IP, TCP, Decoded}, State),
    {next_state, NextStateName, StateNew, Timeout};

state_fin_wait_1( % Ack, payload_size == 0
  {Direction, % Close_initiator
   IP, 
   #tcp{ack=1, syn=0, fin=0, rst=0}=TCP, 
   #decoded{payload_size = 0} = Decoded
  }, State) when 
      Direction == State#state.close_initiator -> 
    {ok, NextStateName, Timeout, StateNew }= handle_payload(?current_function_name(), state_fin_wait_1, {Direction, IP, TCP, Decoded}, State),
    {next_state, NextStateName, StateNew, Timeout};

state_fin_wait_1( % Fin, optional payload
  {Direction,  % Close responder
   IP, 
   #tcp{ack=0, syn=0, fin=1, rst=0}=TCP, 
   #decoded{payload_size = 0} = Decoded
  }, State) when 
      Direction == State#state.close_responder,
      State#state.fin_ack_received == true -> % when Ack for Fin has been received before
    {ok, NextStateName, Timeout, StateNew }= handle_payload(?current_function_name(), state_closing, {Direction, IP, TCP, Decoded}, State),
    {next_state, NextStateName, StateNew, Timeout};

state_fin_wait_1( % Rst
  {Direction, % Close responder
   IP, 
   #tcp{rst=1}=TCP, 
   Decoded
  }, State) when 
      Direction == State#state.close_responder -> 
    {ok, NextStateName, Timeout, StateNew}= handle_reset(?current_function_name(), state_closing, {Direction, IP, TCP, Decoded}, State),
    {next_state, NextStateName, StateNew, Timeout};

state_fin_wait_1( % Rst by connection close initiator 
  {Direction, % Close initiator
   IP, 
   #tcp{rst=1}=TCP, 
   Decoded
  }, State) ->
    {ok, NextStateName, Timeout, StateNew}= handle_reset(?current_function_name(), state_time_wait, {Direction, IP, TCP, Decoded}, State),
    {next_state, NextStateName, StateNew, Timeout};

state_fin_wait_1( % Syn-Ack repeatition by connection initiator, connection responder had responded with FIN
  {Direction = initiator, 
   IP, 
   #tcp{ack=1, syn=1, fin=0, rst=0}=TCP, 
   #decoded{payload_size = 0} = Decoded
  }, State) when
      Direction == State#state.close_responder -> 
    {ok, Timeout, StateNew}= handle_retransmission(NextStateName = ?current_function_name(), {Direction, IP, TCP, Decoded}, State),
    {next_state, NextStateName, StateNew, Timeout}.

state_fin_wait_2(
  {Direction, 
   IP, 
   #tcp{ack=1, syn=0, fin=0, rst=0}=TCP, % Ack retransmission from close initiator
   Decoded
  }, State) when
      Direction == State#state.close_initiator-> 
    {ok, Timeout, StateNew}= handle_retransmission(NextStateName = ?current_function_name(), {Direction, IP, TCP, Decoded}, State),
    {next_state, NextStateName, StateNew, Timeout};

state_fin_wait_2( % Ack retransmission from close responder
  {Direction, 
   IP, 
   #tcp{ack=1, syn=0, fin=0, rst=0}=TCP, 
   Decoded
  }, State) when
      Direction == State#state.close_responder -> 
    {ok, Timeout, StateNew}= handle_retransmission(NextStateName = ?current_function_name(), {Direction, IP, TCP, Decoded}, State),
    {next_state, NextStateName, StateNew, Timeout};

state_fin_wait_2( % Fin-Ack retransmission
  {Direction, 
   IP, 
   #tcp{ack=1, syn=0, fin=1, rst=0}=TCP, 
   Decoded
  }, State) when
      Direction == State#state.close_initiator-> 
    {ok, Timeout, StateNew}= handle_retransmission(NextStateName = ?current_function_name(), {Direction, IP, TCP, Decoded}, State),
    {next_state, NextStateName, StateNew, Timeout};

state_fin_wait_2( % Fin-Ack or Fin, payload
  {Direction, % close_responder
   IP, 
   #tcp{ack=1, syn=0, fin=1, rst=0}=TCP, 
   Decoded
  }, State) when
      Direction == State#state.close_responder->
    {ok, NextStateName, Timeout, StateNew }= handle_payload(?current_function_name(), state_time_wait, {Direction, IP, TCP, Decoded}, State),
    {next_state, NextStateName, StateNew, Timeout};

state_fin_wait_2( % Rst by connection close initiator
  {Direction, 
   IP, 
   #tcp{rst=1}=TCP, 
   #decoded{payload_size = 0} = Decoded
  }, State) when
      Direction == State#state.close_initiator-> 
    {ok, NextStateName, Timeout, StateNew}= handle_reset(?current_function_name(), state_time_wait, {Direction, IP, TCP, Decoded}, State),
    {next_state, NextStateName, StateNew, Timeout};

state_fin_wait_2( % Rst by connection close responder
  {Direction, 
   IP, 
   #tcp{rst=1}=TCP, 
   Decoded
  }, State) when
      Direction == State#state.close_responder-> 
    {ok, NextStateName, Timeout, StateNew}= handle_reset(?current_function_name(), state_time_wait, {Direction, IP, TCP, Decoded}, State),
    {next_state, NextStateName, StateNew, Timeout}.

state_closing(
  {Direction, % Ack
   IP, 
   #tcp{ack=1, syn=0, fin=0, rst=0}=TCP, 
   Decoded
  }, State) when
      Direction == State#state.close_initiator -> 
    {ok, NextStateName, Timeout, StateNew }= handle_payload(?current_function_name(), state_time_wait, {Direction, IP, TCP, Decoded}, State),
    {next_state, NextStateName, StateNew, Timeout};

state_closing( % Rst
  {Direction, % initiator or responder 
   IP, 
   #tcp{rst=1}=TCP, 
   Decoded
  }, State) -> 
    {ok, NextStateName, Timeout, StateNew}= handle_reset(?current_function_name(), state_time_wait, {Direction, IP, TCP, Decoded}, State),
    {next_state, NextStateName, StateNew, Timeout}.

state_time_wait( % Ack retransmission
  {Direction, 
   IP, 
   #tcp{ack=1, syn=0, fin=0, rst=0}=TCP, 
   Decoded
  }, State) when
      Direction == State#state.close_responder-> 
    {ok, Timeout, StateNew}= handle_retransmission(NextStateName = ?current_function_name(), {Direction, IP, TCP, Decoded}, State),
    {next_state, NextStateName, StateNew, 10000};

state_time_wait( % Fin-Ack retransmission
  {Direction, 
   IP, 
   #tcp{ack=1, syn=0, fin=1, rst=0}=TCP, 
   Decoded
  }, State) when
      Direction == State#state.close_responder-> 
    {ok, Timeout, StateNew}= handle_retransmission(NextStateName = ?current_function_name(), {Direction, IP, TCP, Decoded}, State),
    {next_state, NextStateName, StateNew, 10000};

state_time_wait(
  {Direction, 
   IP, 
   #tcp{ack=1, syn=0, fin=0, rst=0}=TCP, 
   Decoded
  }, State) when
      Direction == State#state.close_initiator -> 
    {ok, Timeout, StateNew}= handle_retransmission(NextStateName = ?current_function_name(), {Direction, IP, TCP, Decoded}, State),
    {next_state, NextStateName, StateNew, 10000};

state_time_wait( % Fin-Ack / Fin retransmission
  {Direction, % initiator or responder
   IP, 
   #tcp{syn=0, fin=1, rst=0}=TCP, 
   Decoded
  }, State) -> 
    {ok, Timeout, StateNew}= handle_retransmission(NextStateName = ?current_function_name(), {Direction, IP, TCP, Decoded}, State),
    {next_state, NextStateName, StateNew, 10000};

state_time_wait( % Rst
  {Direction, % initiator or responder
   IP, 
   #tcp{rst=1}=TCP, 
   Decoded
  }, State) -> 
    {ok, NextStateName, Timeout, StateNew}= handle_reset(?current_function_name(), state_time_wait, {Direction, IP, TCP, Decoded}, State),
    {next_state, NextStateName, StateNew, 10000};

state_time_wait(timeout, State) ->
    error_logger:warning_msg("Closing Instance: ~p in state time_wait, ~n State_name, Direction, Ack, Syn, Fin, Rst, TCP#tcp.seqno, TCP#tcp.ackno, TCP#tcp.win, Payload_size_ ~nsent packets: ~p, sent_bytes: ~p~n", [State#state.instance, State#state.sent_packets, State#state.sent_bytes]),
    StateNew = State, 
    {stop, shutdown, StateNew}.

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
    (smaller_or_equal32(RCV_NXT, SEG_SEQ) and smaller32(SEG_SEQ, modulo32bit(RCV_NXT + RCV_WND)));

sequence_no_in_window(SEG_SEQ, RCV_NXT, RCV_WND, SEG_LEN) ->
    (smaller_or_equal32(RCV_NXT, SEG_SEQ) and smaller32(SEG_SEQ, modulo32bit(RCV_NXT + RCV_WND)))
	or (smaller_or_equal32(RCV_NXT, SEG_SEQ) and smaller32((modulo32bit(SEG_SEQ + SEG_LEN +1)), modulo32bit(RCV_NXT + RCV_WND))).

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

%% See RFC 1982 for Serial Number Arithmetic 


compare32(I1, I2) ->
    compareMod32(I1 band 16#FFFFFFFF, I2 band 16#FFFFFFFF).

compareMod32(I1, I2) when I1 == I2 ->
    equal;

compareMod32(I1, I2) when (I1 < I2) and ((I2 - I1) < 16#80000000) ->
    less;

compareMod32(I1, I2) when (I1 > I2) and ((I1 - I2) > 16#80000000) ->
    less;

compareMod32(I1, I2) when (I1 < I2) and ((I2 - I1) > 16#80000000) ->
    greater;

compareMod32(I1, I2) when (I1 > I2) and ((I1 - I2) < 16#80000000) ->
    greater;

compareMod32(_I1, _I2) ->
    undef.


smaller32(I1, I2) ->
    case compare32(I1, I2) of
	equal   -> false;
	less    -> true;
	greater -> false;
	undef   -> false
    end.	



smaller_or_equal32(I1, I2) ->
    case compare32(I1, I2) of
	equal   -> true;
	less    -> true;
	greater -> false;
	undef   -> false
    end.

ack_valid(_SEG_ACK, undefined, _SND_WND) ->
    valid_ack;

ack_valid(SEG_ACK, SND_UNA, SND_WND) ->
    case (modulo32bit(SND_UNA) == modulo32bit(SEG_ACK)) of
	true ->
	    repetition_ack;
	false ->
	    case (smaller32(SND_UNA, SEG_ACK) and smaller_or_equal32(SEG_ACK, SND_UNA+SND_WND)) of
   		true ->
		    valid_ack;
        	false ->
		    invalid_ack
            end
    end.


test_ack_valid(Direction=initiator, State, SEG_ACK) ->
    ack_valid(SEG_ACK, State#state.initiator_SND_UNA, calculate_window(Direction, State));

test_ack_valid(Direction=responder, State, SEG_ACK) ->
    ack_valid(SEG_ACK, State#state.responder_SND_UNA, calculate_window(Direction, State)).

%% if any of the side did not set the window scale in the options filed, the scale is not used (See RFC 1323)



test_sequence_no_in_window(Direction=initiator, State, SEG_SEQ) ->
    sequence_no_in_window(SEG_SEQ, State#state.initiator_RCV_NXT,
                          calculate_window(reverse(Direction), State), 0);

test_sequence_no_in_window(Direction=responder, State, SEG_SEQ) ->
    sequence_no_in_window(SEG_SEQ, State#state.responder_RCV_NXT,
                          calculate_window(reverse(Direction), State), 0).


test_sequence_no_in_window(Direction=initiator, State, SEG_SEQ, SEG_LEN) ->
    sequence_no_in_window(SEG_SEQ, State#state.initiator_RCV_NXT,
			  calculate_window(reverse(Direction), State), SEG_LEN);

test_sequence_no_in_window(Direction=responder, State, SEG_SEQ, SEG_LEN) ->
    sequence_no_in_window(SEG_SEQ, State#state.responder_RCV_NXT,
			  calculate_window(reverse(Direction), State), SEG_LEN).

calculate_window(initiator = _Direction, State) ->
    calculate_window(State#state.initiator_RCV_WND, State#state.initiator_RCV_WND_SCALE, State#state.responder_RCV_WND_SCALE);

calculate_window(responder = _Direction, State) ->
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

storeState_RCV_NXT(Direction=initiator,     State,  SEG_SEQ, true) ->
    State#state{initiator_RCV_NXT = forward_sequence_no(modulo32bit(SEG_SEQ + 1), State#state.initiator_RCV_NXT, calculate_window(Direction, State))};

storeState_RCV_NXT(Direction=initiator,     State,  SEG_SEQ, false) ->
    State#state{initiator_RCV_NXT = forward_sequence_no(modulo32bit(SEG_SEQ + 0), State#state.initiator_RCV_NXT, calculate_window(Direction, State))};

storeState_RCV_NXT(Direction=responder,     State,  SEG_SEQ, true) ->
    State#state{responder_RCV_NXT = forward_sequence_no(modulo32bit(SEG_SEQ + 1), State#state.responder_RCV_NXT, calculate_window(Direction, State))};

storeState_RCV_NXT(Direction=responder,     State,  SEG_SEQ, false) ->
    State#state{responder_RCV_NXT = forward_sequence_no(modulo32bit(SEG_SEQ + 0), State#state.responder_RCV_NXT, calculate_window(Direction, State))}.

storeState_RCV_NXT(Direction=initiator, #state{initiator_RCV_NXT = RCV_NXT} = State, SEG_SEQ, SEG_LEN, true = _Syn_or_Fin)
  when (RCV_NXT == SEG_SEQ)->
    %%error_logger:info_msg("Ports: ~p <-> ~p RCV_NXT:~p  matches SEG_SEQ:~p~n"), [State#state.initiator_port, State#state.responder_port, RCV_NXT, SEG_SEQ]),
    State#state{initiator_RCV_NXT = forward_sequence_no(modulo32bit(SEG_SEQ+SEG_LEN +1), State#state.initiator_RCV_NXT, calculate_window(Direction, State))};

storeState_RCV_NXT(Direction=initiator, #state{initiator_RCV_NXT = RCV_NXT} = State, SEG_SEQ, SEG_LEN, false = _Syn_or_Fin)
  when (RCV_NXT == SEG_SEQ)->
    %%error_logger:info_msg("Ports: ~p <-> ~p RCV_NXT:~p  matches SEG_SEQ:~p~n", [State#state.initiator_port, State#state.responder_port,RCV_NXT, SEG_SEQ]),
    State#state{initiator_RCV_NXT = forward_sequence_no(modulo32bit(SEG_SEQ+SEG_LEN + 0), State#state.initiator_RCV_NXT, calculate_window(Direction, State))};

storeState_RCV_NXT(Direction=responder, #state{responder_RCV_NXT = RCV_NXT} = State, SEG_SEQ, SEG_LEN, true = _Syn_or_Fin)
  when (RCV_NXT == SEG_SEQ)->
    %%error_logger:info_msg("Ports: ~p <-> ~p RCV_NXT:~p  matches SEG_SEQ:~p~n", [State#state.responder_port, State#state.initiator_port,RCV_NXT, SEG_SEQ]),
    State#state{responder_RCV_NXT = forward_sequence_no(modulo32bit(SEG_SEQ+SEG_LEN +1), State#state.responder_RCV_NXT, calculate_window(Direction, State))};

storeState_RCV_NXT(Direction=responder,  #state{responder_RCV_NXT = RCV_NXT} = State, SEG_SEQ, SEG_LEN, false = _Syn_or_Fin)
  when (RCV_NXT == SEG_SEQ)->
    %%error_logger:info_msg("Ports: ~p <-> ~p RCV_NXT:~p  matches SEG_SEQ:~p~n", [State#state.responder_port, State#state.initiator_port,RCV_NXT, SEG_SEQ]),
    State#state{responder_RCV_NXT = forward_sequence_no(modulo32bit(SEG_SEQ+SEG_LEN +0), State#state.responder_RCV_NXT, calculate_window(Direction, State))};

storeState_RCV_NXT(_Direction=initiator,  #state{initiator_RCV_NXT = _RCV_NXT} = State, _SEG_SEQ, _SEG_LEN,  _Syn_or_Fin) ->
    error_logger:info_msg("Ports: ~p <-> ~p RCV_NXT:~p does not match SEG_SEQ:~p~n", [State#state.initiator_port, State#state.responder_port, _RCV_NXT, _SEG_SEQ]),
    State;

storeState_RCV_NXT(_Direction=responder,  #state{responder_RCV_NXT = _RCV_NXT} = State, _SEG_SEQ, _SEG_LEN,  _Syn_or_Fin) ->
    error_logger:info_msg("Ports: ~p <-> ~p RCV_NXT:~p does not match SEG_SEQ:~p~n", [State#state.responder_port, State#state.initiator_port,_RCV_NXT, _SEG_SEQ]),
    State.

storeState_SND_UNA(_, State, _SEG_ACK, false) ->
    State;

storeState_SND_UNA(initiator = Direction, State, SEG_ACK, true) ->
    case test_ack_valid(Direction, State, SEG_ACK) of
	valid_ack ->
	    %%error_logger:info_msg("Valid Ack!! Forwarding SND_UNA from:  ~p to: ~p~n",[State#state.initiator_SND_UNA, add_modulo_32bit(SEG_ACK,0)]),
	    State#state{initiator_SND_UNA = add_modulo_32bit(SEG_ACK,0)};
	repetition_ack ->
	    %%error_logger:info_msg("Information: Repetition Ack:~p received~n",[SEG_ACK]),
	    State;
	invalid_ack ->
            _SND_UNA = State#state.initiator_SND_UNA,
            _SND_WND = calculate_window(Direction, State),
	    %%error_logger:error_msg("Error: ~ninvalid Ack: ~p for SND_UNA: ~p SND_WND: ~p and SND_UNA+SND_WND: ~p received~n",[SEG_ACK, SND_UNA, SND_WND, SND_UNA+SND_WND]),
	    State
    end;

storeState_SND_UNA(responder = Direction, State, SEG_ACK, true) ->
    case test_ack_valid(Direction, State, SEG_ACK) of
	valid_ack ->
	    %%error_logger:info_msg("Valid Ack!! Forwarding SND_UNA from:  ~p to: ~p~n",[State#state.responder_SND_UNA, add_modulo_32bit(SEG_ACK,0)]),
	    State#state{responder_SND_UNA = add_modulo_32bit(SEG_ACK,0)};
	repetition_ack ->
	    %%error_logger:info_msg("Information: Repetition Ack:~p received~n",[SEG_ACK]),
	    State;
	invalid_ack ->
            _SND_UNA = State#state.responder_SND_UNA,
            _SND_WND = calculate_window(Direction, State),
	    %%error_logger:error_msg("Error: ~ninvalid Ack: ~p for SND_UNA: ~p SND_WND: ~p and SND_UNA+SND_WND: ~p received~n",[SEG_ACK, SND_UNA, SND_WND, SND_UNA+SND_WND]),
	    State
    end.


storeState_SND_WND(initiator = _Direction, State, SEG_WND) ->
    State#state{initiator_RCV_WND = SEG_WND};

storeState_SND_WND(responder = _Direction, State, SEG_WND) ->
    State#state{responder_RCV_WND = SEG_WND}.

storeState_Payload(_Direction=initiator, State, _SEG_SEQ, 0 =_Payload_size, <<>> = _Payload) ->
    State; %% ignore zero payload length packages

storeState_Payload(_Direction=responder, State, _SEG_SEQ, 0 =_Payload_size, <<>> = _Payload) ->
    State; %% ignore zero payload length packages

storeState_Payload(_Direction=initiator, State, SEG_SEQ, Payload_size, Payload) ->
    StateNew1 = State#state{initiator_retransmission_index = determine_retransmission_index(SEG_SEQ, State#state.initiator_last_SEG_SEQ, State#state.initiator_retransmission_index)},
    StateNew  = StateNew1#state{initiator_payload_store = 
				    queue:in({SEG_SEQ, StateNew1#state.initiator_retransmission_index, Payload_size, Payload}, StateNew1#state.initiator_payload_store), initiator_last_SEG_SEQ = SEG_SEQ},
    %%error_logger:info_msg("PayloadStore Direction ~p contains now ~p packages~n",[_Direction, length(StateNew#state.initiator_payload_store)]),
    StateNew;

storeState_Payload(_Direction=responder, State, SEG_SEQ, Payload_size, Payload) ->
    StateNew1 = State#state{responder_retransmission_index = determine_retransmission_index(SEG_SEQ, State#state.responder_last_SEG_SEQ, State#state.responder_retransmission_index)},
    StateNew  = StateNew1#state{responder_payload_store = 
				    queue:in({SEG_SEQ, StateNew1#state.responder_retransmission_index, Payload_size, Payload}, StateNew1#state.responder_payload_store), responder_last_SEG_SEQ = SEG_SEQ},
    %%error_logger:info_msg("PayloadStore Direction ~p contains now ~p packages~n",[_Direction, length(StateNew#state.responder_payload_store)]),
    StateNew.

storeState_SND_WND_SCALE(_Direction= initiator, State, ShiftCount) ->
    State#state{initiator_RCV_WND_SCALE = ShiftCount};

storeState_SND_WND_SCALE(_Direction= responder, State, ShiftCount) ->
    State#state{responder_RCV_WND_SCALE = ShiftCount}.

determine_retransmission_index(_SEG_SEQ, undefined, Retransmission_Index) ->
    Retransmission_Index;

determine_retransmission_index(SEG_SEQ, Last_SEG_SEQ, Retransmission_Index) ->
    %% The retransmission index will be increased, when the sequence number is reduced in a subsequent packet
    case smaller32(SEG_SEQ, Last_SEG_SEQ) of
    	true ->
            Retransmission_Index +1 ;
        false ->
            Retransmission_Index
    end.

set_close_initiator(_Direction=initiator, State) ->
    State#state{close_initiator = initiator, close_responder = responder};

set_close_initiator(_Direction=responder, State) ->
    State#state{close_initiator = responder, close_responder = initiator}.

log_initiator_responder(_StateName, _SEG_SEQ, _SEG_ACK, _SEG_WND, _State) ->
    %%error_logger:info_msg("State: ~p, SEG_SEQ: ~w, SEG_ACK: ~w, SEG_WND: ~w~n", [_StateName, _SEG_SEQ, _SEG_ACK, _SEG_WND]),
    %%error_logger:warning_msg("i_address: ~p, i_port : ~w, i_RCV_WND ~w, i_SND_UNA: ~w, i_RCV_NXT:~w~n", [_State#state.initiator_address, _State#state.initiator_port, _State#state.initiator_RCV_WND, _State#state.initiator_SND_UNA, _State#state.initiator_RCV_NXT]),
    %%error_logger:info_msg("r_address: ~p, r_port : ~w, r_RCV_WND ~w, r_SND_UNA: ~w, r_RCV_NXT: ~w~n", [_State#state.responder_address, _State#state.responder_port, _State#state.responder_RCV_WND, 	_State#state.responder_SND_UNA, _State#state.responder_RCV_NXT]),
    true.


forward_payload(ServerPids, Source, Destination, Payload) ->
    forward_payload(ServerPids, Source, Destination, Payload, 0, 0).

forward_payload([ServerPid|ServerPids], {Source_address, Source_port} = _Source,{Destination_address, Destination_port} = _Destination, Payload, Sent_packets, Sent_bytes) ->
    error_logger:info_msg("Sending data: ServerPid: ~p, Source: ~p:~p, Destination: ~p:~p, Payload_size ~p~n", [ServerPid, Source_address, Source_port, Destination_address, Destination_port, byte_size(Payload)]),
    Sent_bytesNew = Sent_bytes +byte_size(Payload), 
    ok= gen_server:call(ServerPid, {payload_section, Source_address, Source_port, Destination_address, Destination_port, Payload}, infinity),
    Sent_packetsNew = Sent_packets+1, 
    forward_payload(ServerPids, {Source_address, Source_port}, {Destination_address, Destination_port}, Payload, Sent_packetsNew, Sent_bytesNew);

forward_payload([], _Source, _Destination, _Payload, Sent_packets, Sent_bytes) ->
    {ok, Sent_packets, Sent_bytes}.

%% Here Direction is always the opposite side, as Ack forwards the packages of the peer side
forward_stream_ack_payload_store(Direction=responder, Fin, Source, Destination, #state{initiator_ack_payload_store = Payload_store} = State) when byte_size(Payload_store) >= 1500->
    <<Payload_forward:1500/binary-unit:8, Payload_rest/binary>> = Payload_store,
    {ok, Sent_packets, Sent_bytes} = forward_payload(State#state.child_worker_list,  Source, Destination, Payload_forward),
    StateNew  = State#state{initiator_ack_payload_store = Payload_rest, sent_packets = State#state.sent_packets + Sent_packets, sent_bytes = State#state.sent_bytes + Sent_bytes},
    forward_stream_ack_payload_store(Direction, Fin, Source, Destination, StateNew);

forward_stream_ack_payload_store(Direction=initiator, Fin, Source, Destination, #state{responder_ack_payload_store = Payload_store} = State) when byte_size(Payload_store) >= 1500->
    <<Payload_forward:1500/binary-unit:8, Payload_rest/binary>> = Payload_store,
    {ok, Sent_packets, Sent_bytes} = forward_payload(State#state.child_worker_list,  Source, Destination, Payload_forward),
    StateNew  = State#state{responder_ack_payload_store = Payload_rest, sent_packets = State#state.sent_packets + Sent_packets, sent_bytes = State#state.sent_bytes + Sent_bytes},
    forward_stream_ack_payload_store(Direction, Fin, Source, Destination, StateNew);

forward_stream_ack_payload_store(_Direction=responder, true = _Fin, Source, Destination, #state{initiator_ack_payload_store = Payload_store} = State)->
    {ok, Sent_packets, Sent_bytes} = forward_payload(State#state.child_worker_list, Source, Destination, Payload_store),
    StateNew  = State#state{initiator_ack_payload_store = <<>>, sent_packets = State#state.sent_packets + Sent_packets, sent_bytes = State#state.sent_bytes + Sent_bytes},
    StateNew;

forward_stream_ack_payload_store(_Direction=initiator, true = _Fin, Source, Destination, #state{responder_ack_payload_store = Payload_store} = State)->
    {ok, Sent_packets, Sent_bytes} = forward_payload(State#state.child_worker_list, Source, Destination, Payload_store),
    StateNew  = State#state{responder_ack_payload_store = <<>>, sent_packets = State#state.sent_packets + Sent_packets, sent_bytes = State#state.sent_bytes + Sent_bytes},
    StateNew;

forward_stream_ack_payload_store(_Direction=initiator, false = _Fin, _Source, _Destination, State) ->
    State;

forward_stream_ack_payload_store(_Direction=responder, false = _Fin, _Source, _Destination, State) ->
    State.


checkPayloadReceptionBuffer(_Direction=initiator, false = _Ack, _SEG_ACK, _Syn_or_Fin, #state{} = State) ->
    error_logger:info_msg("Received: Package with Ack = false in Direction ~p~n", [_Direction]),
    State;

checkPayloadReceptionBuffer(_Direction=responder, false = _Ack, _SEG_ACK, _Syn_or_Fin, #state{} = State) ->
    error_logger:info_msg("Received: Package with Ack = false in Direction ~p~n", [_Direction]),
    State;

checkPayloadReceptionBuffer(Direction=initiator, true = Ack, SEG_ACK, Syn_or_Fin, #state{initiator_RCV_NXT = RCV_NXT, initiator_payload_store = Payload_queue} = State) ->
    QueueList = queue:to_list(Payload_queue),
    Filter_binary_out_fun = fun({SEG_SEQ, Retransmission_Index, Payload_size, _Payload}) -> {SEG_SEQ, SEG_SEQ + Payload_size, Retransmission_Index, Payload_size} end,
    Filtered_binary_out = lists:map(Filter_binary_out_fun, QueueList),
    error_logger:info_msg("checkPayloadReceptionBuffer: Bufferstate in Direction ~p has RCV_NXT: ~p, SEG_ACK: ~p and content: ~n~p~n", [Direction, RCV_NXT, SEG_ACK, Filtered_binary_out]),
    {QueueValue, Payload_queue_New} = queue:out(Payload_queue),
    case QueueValue of
	empty ->
            %%error_logger:info_msg("Check payload_store: Payloadstore in Direction ~p is empty~n", [Direction]),
	    State;
        {value, {SEG_SEQ, Retransmission_Index, Payload_size, Payload}} -> 
	    RCV_NXT32 = modulo32bit(RCV_NXT),
	    SEG_SEQ32 = modulo32bit(SEG_SEQ),
	    SEG_ACK32 = modulo32bit(SEG_ACK),
	    %% test SEG_SEQ32 =< RCV_NXT32 =< SEG_ACK is not ever assured, the acknowledgement may not acknowlege the latest packet
	    %% test SEG_SEQ32 =< RCV_NXT32
	    %% test SEG_SEQ32 =< SEG_ACK =< RCV_NXT32 + Window
	    case smaller_or_equal32(SEG_SEQ32, SEG_ACK32) of
		true -> % SEG_SEQ =< SEG_ACK
		    RCV_NXT_plus_Window32 = add_modulo_32bit(RCV_NXT32, calculate_window(reverse(Direction), State)),
		    case smaller_or_equal32(SEG_ACK32, RCV_NXT_plus_Window32) of
			true -> % SEG_ACK =< RCV_NXT + Window
			    %%error_logger:info_msg("Check payload_store: Payloadstore in Direction ~p has first payload with:~p bytes~n", [Direction, Payload_size]),
                            case smaller_or_equal32(SEG_SEQ32, RCV_NXT32) of 
				true -> % RCV_NXT32 >= SEG_SEQ32
				    Delta_overlap_ignore = add_modulo_32bit(RCV_NXT32, -SEG_SEQ32),
				    case Delta_overlap_ignore < Payload_size of % if 
					true ->
					    Ack_payload_store = State#state.initiator_ack_payload_store,
					    %% Consider overlapping payload strategy
					    case State#state.overlapping_payload_strategy of
						last_wins ->
						    Ack_payload_store_size = byte_size(Ack_payload_store),
						    if 
							Ack_payload_store_size > Delta_overlap_ignore -> 
							    StateNew1 = State#state{initiator_ack_payload_store = <<Ack_payload_store:(Ack_payload_store_size - Delta_overlap_ignore)/binary, Payload/binary>>};
							true ->
							    <<_Ignore:Delta_overlap_ignore/binary, Payload_non_duplicate/binary>> = <<Payload/binary>>,
							    StateNew1 = State#state{initiator_ack_payload_store = <<Ack_payload_store/binary, Payload_non_duplicate/binary>>}
						    end;
						first_wins ->
						    <<_Ignore:Delta_overlap_ignore/binary, Payload_non_duplicate/binary>> = <<Payload/binary>>,
						    StateNew1 = State#state{initiator_ack_payload_store = <<Ack_payload_store/binary, Payload_non_duplicate/binary>>}
					    end,
					    StateNew2 = storeState_RCV_NXT(Direction, StateNew1, SEG_SEQ, Payload_size-Delta_overlap_ignore, _Syn_or_Fin_for_peer_direction = false),
					    StateNew  = StateNew2#state{initiator_payload_store = Payload_queue_New},
					    checkPayloadReceptionBuffer(Direction, Ack, SEG_ACK32, Syn_or_Fin, StateNew);
					false ->
					    error_logger:error_msg("Check payload failed as no new data available!!!!Direction: ~p, SEG_SEQ: ~p, RCV_NXT:~p, Payload_size: ~p~n",[Direction, SEG_SEQ, RCV_NXT, Payload_size]),
					    StateNew  = State#state{initiator_payload_store = Payload_queue_New},
					    checkPayloadReceptionBuffer(Direction, Ack, SEG_ACK32, Syn_or_Fin, StateNew)
				    end;
				false -> % RCV_NXT32 < SEG_SEQ32
				    error_logger:error_msg("checkPayloadReceptionBuffer:Queueing !!!!, RCV_NXT < SEG_SEQ, Direction: ~p, SEG_SEQ: ~p:~p, SEG_ACK:~p, RCV_NXT:~p, Window:~p~n",[Direction, SEG_SEQ, SEG_SEQ + Payload_size, SEG_ACK, RCV_NXT, calculate_window(reverse(Direction), State)]),
				    StateNew1 = State#state{initiator_payload_store = Payload_queue_New},
				    SmallerFun = fun({SEG_SEQA, Retransmission_IndexA, _, _},{SEG_SEQB, Retransmission_IndexB, _, _}) -> 
							 if 
							     Retransmission_IndexA < Retransmission_IndexB -> true;
							     Retransmission_IndexA > Retransmission_IndexB -> false;
							     true -> 
								 smaller32(SEG_SEQA, SEG_SEQB) % SEG_SEQA < SEG_SEQB mod 32 bit
							 end
						 end,
				    StateNew  = StateNew1#state{initiator_sack_store = lists:usort(SmallerFun, 
												   [{SEG_SEQ, Retransmission_Index, Payload_size, Payload}|StateNew1#state.initiator_sack_store]), initiator_payload_store = Payload_queue_New},
				    Filter_binary_out_fun2 = fun({FunSEG_SEQ, FunRetransmission_Index, FunPayloadLength, _FunPayload}) -> {FunSEG_SEQ, FunSEG_SEQ + FunPayloadLength,    
																	   FunRetransmission_Index, FunPayloadLength} end,
				    Filtered_binary_out2 = lists:map(Filter_binary_out_fun2, StateNew#state.initiator_sack_store),
				    error_logger:info_msg("checkPayloadReceptionBuffer: SAck Bufferstate after Queueing in Direction ~p has RCV_NXT:~p and content: ~n~p~n", [Direction, RCV_NXT, Filtered_binary_out2]),
				    checkPayloadReceptionBuffer(Direction, Ack, SEG_ACK32, Syn_or_Fin, StateNew)
			    end;
			false -> % SEG_ACK > RCV_NXT + Window
			    %% Acknowledgement out of Window
			    error_logger:info_msg("checkPayloadReceptionBuffer:Acknowledgement out of Window, Direction:~p, SEG_SEQ32:~p:~p ,Peer:SEG_ACK32:~p, RCV_NXT:~p, Window:~p~n", [Direction, SEG_SEQ32, SEG_SEQ32+Payload_size, SEG_ACK32, RCV_NXT, calculate_window(reverse(Direction), State)]),
			    State#state{initiator_payload_store = Payload_queue_New}
		    end;
		false -> % SEG_SEQ > SEG_ACK
                    %% Queue in Sack Queue, if SEG_SEQ32 =< RCV_NXT32 + Window
		    RCV_NXT_plus_Window32 = add_modulo_32bit(RCV_NXT32, calculate_window(reverse(Direction), State)),
		    case smaller_or_equal32(SEG_SEQ32, RCV_NXT_plus_Window32) of
			true -> % SEG_SEQ32 =< RCV_NXT +Window
          		    error_logger:error_msg("checkPayloadReceptionBuffer:Queueing !!!!, SEG_SEQ > SEG_ACK, SEG_SEQ =< RCV_NXT + Window, Direction: ~p, SEG_SEQ: ~p:~p, SEG_ACK:~p, RCV_NXT:~p, Window:~p~n",[Direction, SEG_SEQ, SEG_SEQ + Payload_size, SEG_ACK, RCV_NXT, calculate_window(reverse(Direction), State)]),
			    StateNew1 = State#state{initiator_payload_store = Payload_queue_New},
			    SmallerFun = fun({SEG_SEQA, Retransmission_IndexA, _, _},{SEG_SEQB, Retransmission_IndexB, _, _}) -> 
						 if 
						     Retransmission_IndexA < Retransmission_IndexB -> true;
						     Retransmission_IndexA > Retransmission_IndexB -> false;
						     true -> 
							 smaller32(SEG_SEQA, SEG_SEQB) % SEG_SEQA < SEG_SEQB mod 32 bit
						 end
					 end,
			    StateNew  = StateNew1#state{initiator_sack_store = lists:usort(SmallerFun, 
											   [{SEG_SEQ, Retransmission_Index, Payload_size, Payload}|StateNew1#state.initiator_sack_store]),
							initiator_payload_store = Payload_queue_New},
                            Filter_binary_out_fun2 = fun({FunSEG_SEQ, FunRetransmission_Index, FunPayloadLength, _FunPayload}) -> {FunSEG_SEQ, FunSEG_SEQ + FunPayloadLength,           FunRetransmission_Index, FunPayloadLength} end,
                            Filtered_binary_out2 = lists:map(Filter_binary_out_fun2, StateNew#state.initiator_sack_store),
                            error_logger:info_msg("checkPayloadReceptionBuffer: SAck Bufferstate after Queueing in Direction ~p has RCV_NXT:~p and content: ~n~p~n", [Direction, RCV_NXT, Filtered_binary_out2]),
			    checkPayloadReceptionBuffer(Direction, Ack, SEG_ACK32, Syn_or_Fin, StateNew);
			false -> % SEG_SEQ32 > SEG_ACK
			    %% Acknowledgement out of Window
			    error_logger:info_msg("checkPayloadReceptionBuffer:Acknowledgement out of Window, Direction:~p, SEG_SEQ32:~p:~p ,Peer:SEG_ACK32:~p, RCV_NXT:~p, Window:~p~n", [Direction, SEG_SEQ32, SEG_SEQ32+Payload_size, SEG_ACK32, RCV_NXT, calculate_window(reverse(Direction), State)]),
			    State#state{initiator_payload_store = Payload_queue_New}
		    end
	    end
    end;


checkPayloadReceptionBuffer(Direction=responder, true = Ack, SEG_ACK, Syn_or_Fin, #state{responder_RCV_NXT = RCV_NXT, responder_payload_store = Payload_queue} = State) ->
    QueueList = queue:to_list(Payload_queue),
    Filter_binary_out_fun = fun({SEG_SEQ, Retransmission_Index, Payload_size, _Payload}) -> {SEG_SEQ, SEG_SEQ + Payload_size, Retransmission_Index, Payload_size} end,
    Filtered_binary_out = lists:map(Filter_binary_out_fun, QueueList),
    error_logger:info_msg("checkPayloadReceptionBuffer: Bufferstate in Direction ~p has RCV_NXT: ~p, SEG_ACK: ~p and content: ~n~p~n", [Direction, RCV_NXT, SEG_ACK, Filtered_binary_out]),
    {QueueValue, Payload_queue_New} = queue:out(Payload_queue),
    case QueueValue of
	empty ->
            %%error_logger:info_msg("Check payload_store: Payloadstore in Direction ~p is empty~n", [Direction]),
	    State;
        {value, {SEG_SEQ, Retransmission_Index, Payload_size, Payload}} -> 
	    RCV_NXT32 = modulo32bit(RCV_NXT),
	    SEG_SEQ32 = modulo32bit(SEG_SEQ),
	    SEG_ACK32 = modulo32bit(SEG_ACK),
	    %% test SEG_SEQ32 =< RCV_NXT32 =< SEG_ACK is not ever assured, the acknowledgement may not acknowlege the latest packet
	    %% test SEG_SEQ32 =< RCV_NXT32
	    %% test SEG_SEQ32 =< SEG_ACK =< RCV_NXT32 + Window
	    case smaller_or_equal32(SEG_SEQ32, SEG_ACK32) of
		true -> % SEG_SEQ =< SEG_ACK
		    RCV_NXT_plus_Window32 = add_modulo_32bit(RCV_NXT32, calculate_window(reverse(Direction), State)),
		    case smaller_or_equal32(SEG_ACK32, RCV_NXT_plus_Window32) of
			true -> % SEG_ACK =< RCV_NXT + Window
			    %%error_logger:info_msg("Check payload_store: Payloadstore in Direction ~p has first payload with:~p bytes~n", [Direction, Payload_size]),
                            case smaller_or_equal32(SEG_SEQ32, RCV_NXT32) of 
				true -> % RCV_NXT32 >= SEG_SEQ32
				    Delta_overlap_ignore = add_modulo_32bit(RCV_NXT32, -SEG_SEQ32),
				    case Delta_overlap_ignore < Payload_size of % if 
					true ->
					    Ack_payload_store = State#state.responder_ack_payload_store,
					    %% Consider overlapping payload strategy
					    case State#state.overlapping_payload_strategy of
						last_wins ->
						    Ack_payload_store_size = byte_size(Ack_payload_store),
						    if 
							Ack_payload_store_size > Delta_overlap_ignore -> 
							    StateNew1 = State#state{responder_ack_payload_store = <<Ack_payload_store:(Ack_payload_store_size - Delta_overlap_ignore)/binary, Payload/binary>>};
							true ->
							    <<_Ignore:Delta_overlap_ignore/binary, Payload_non_duplicate/binary>> = <<Payload/binary>>,
							    StateNew1 = State#state{responder_ack_payload_store = <<Ack_payload_store/binary, Payload_non_duplicate/binary>>}
						    end;
						first_wins ->
						    <<_Ignore:Delta_overlap_ignore/binary, Payload_non_duplicate/binary>> = <<Payload/binary>>,
						    StateNew1 = State#state{responder_ack_payload_store = <<Ack_payload_store/binary, Payload_non_duplicate/binary>>}
					    end,
					    StateNew2 = storeState_RCV_NXT(Direction, StateNew1, SEG_SEQ, Payload_size-Delta_overlap_ignore, _Syn_or_Fin_for_peer_direction = false),
					    StateNew  = StateNew2#state{responder_payload_store = Payload_queue_New},
					    checkPayloadReceptionBuffer(Direction, Ack, SEG_ACK32, Syn_or_Fin, StateNew);
					false ->
					    error_logger:error_msg("Check payload failed as no new data available!!!!Direction: ~p, SEG_SEQ: ~p, RCV_NXT:~p, Payload_size: ~p~n",[Direction, SEG_SEQ, RCV_NXT, Payload_size]),
					    StateNew  = State#state{responder_payload_store = Payload_queue_New},
					    checkPayloadReceptionBuffer(Direction, Ack, SEG_ACK32, Syn_or_Fin, StateNew)
				    end;
				false -> % RCV_NXT32 < SEG_SEQ32
				    error_logger:error_msg("checkPayloadReceptionBuffer:Queueing !!!!, RCV_NXT < SEG_SEQ, Direction: ~p, SEG_SEQ: ~p:~p, SEG_ACK:~p, RCV_NXT:~p, Window:~p~n",[Direction, SEG_SEQ, SEG_SEQ + Payload_size, SEG_ACK, RCV_NXT, calculate_window(reverse(Direction), State)]),
				    StateNew1 = State#state{responder_payload_store = Payload_queue_New},
				    SmallerFun = fun({SEG_SEQA, Retransmission_IndexA, _, _},{SEG_SEQB, Retransmission_IndexB, _, _}) -> 
							 if 
							     Retransmission_IndexA < Retransmission_IndexB -> true;
							     Retransmission_IndexA > Retransmission_IndexB -> false;
							     true -> 
								 smaller32(SEG_SEQA, SEG_SEQB) % SEG_SEQA < SEG_SEQB mod 32 bit
							 end
						 end,
				    StateNew  = StateNew1#state{responder_sack_store = lists:usort(SmallerFun, 
												   [{SEG_SEQ, Retransmission_Index, Payload_size, Payload}|StateNew1#state.responder_sack_store]), responder_payload_store = Payload_queue_New},
				    Filter_binary_out_fun2 = fun({FunSEG_SEQ, FunRetransmission_Index, FunPayloadLength, _FunPayload}) -> {FunSEG_SEQ, FunSEG_SEQ + FunPayloadLength,    
																	   FunRetransmission_Index, FunPayloadLength} end,
				    Filtered_binary_out2 = lists:map(Filter_binary_out_fun2, StateNew#state.responder_sack_store),
				    error_logger:info_msg("checkPayloadReceptionBuffer: SAck Bufferstate after Queueing in Direction ~p has RCV_NXT:~p and content: ~n~p~n", [Direction, RCV_NXT, Filtered_binary_out2]),
				    checkPayloadReceptionBuffer(Direction, Ack, SEG_ACK32, Syn_or_Fin, StateNew)
			    end;
			false -> % SEG_ACK > RCV_NXT + Window
			    %% Acknowledgement out of Window
			    error_logger:info_msg("checkPayloadReceptionBuffer:Acknowledgement out of Window, Direction:~p, SEG_SEQ32:~p:~p ,Peer:SEG_ACK32:~p, RCV_NXT:~p, Window:~p~n", [Direction, SEG_SEQ32, SEG_SEQ32+Payload_size, SEG_ACK32, RCV_NXT, calculate_window(reverse(Direction), State)]),
			    State#state{responder_payload_store = Payload_queue_New}
		    end;
		false -> % SEG_SEQ > SEG_ACK
                    %% Queue in Sack Queue, if SEG_SEQ32 =< RCV_NXT32 + Window
		    RCV_NXT_plus_Window32 = add_modulo_32bit(RCV_NXT32, calculate_window(reverse(Direction), State)),
		    case smaller_or_equal32(SEG_SEQ32, RCV_NXT_plus_Window32) of
			true -> % SEG_SEQ32 =< RCV_NXT +Window
          		    error_logger:error_msg("checkPayloadReceptionBuffer:Queueing !!!!, SEG_SEQ > SEG_ACK, SEG_SEQ =< RCV_NXT + Window, Direction: ~p, SEG_SEQ: ~p:~p, SEG_ACK:~p, RCV_NXT:~p, Window:~p~n",[Direction, SEG_SEQ, SEG_SEQ + Payload_size, SEG_ACK, RCV_NXT, calculate_window(reverse(Direction), State)]),
			    StateNew1 = State#state{responder_payload_store = Payload_queue_New},
			    SmallerFun = fun({SEG_SEQA, Retransmission_IndexA, _, _},{SEG_SEQB, Retransmission_IndexB, _, _}) -> 
						 if 
						     Retransmission_IndexA < Retransmission_IndexB -> true;
						     Retransmission_IndexA > Retransmission_IndexB -> false;
						     true -> 
							 smaller32(SEG_SEQA, SEG_SEQB) % SEG_SEQA < SEG_SEQB mod 32 bit
						 end
					 end,
			    StateNew  = StateNew1#state{responder_sack_store = lists:usort(SmallerFun, 
											   [{SEG_SEQ, Retransmission_Index, Payload_size, Payload}|StateNew1#state.responder_sack_store]),
							responder_payload_store = Payload_queue_New},
                            Filter_binary_out_fun2 = fun({FunSEG_SEQ, FunRetransmission_Index, FunPayloadLength, _FunPayload}) -> {FunSEG_SEQ, FunSEG_SEQ + FunPayloadLength,           FunRetransmission_Index, FunPayloadLength} end,
                            Filtered_binary_out2 = lists:map(Filter_binary_out_fun2, StateNew#state.responder_sack_store),
                            error_logger:info_msg("checkPayloadReceptionBuffer: SAck Bufferstate after Queueing in Direction ~p has RCV_NXT:~p and content: ~n~p~n", [Direction, RCV_NXT, Filtered_binary_out2]),
			    checkPayloadReceptionBuffer(Direction, Ack, SEG_ACK32, Syn_or_Fin, StateNew);
			false -> % SEG_SEQ32 > SEG_ACK
			    %% Acknowledgement out of Window
			    error_logger:info_msg("checkPayloadReceptionBuffer:Acknowledgement out of Window, Direction:~p, SEG_SEQ32:~p:~p ,Peer:SEG_ACK32:~p, RCV_NXT:~p, Window:~p~n", [Direction, SEG_SEQ32, SEG_SEQ32+Payload_size, SEG_ACK32, RCV_NXT, calculate_window(reverse(Direction), State)]),
			    State#state{responder_payload_store = Payload_queue_New}
		    end
	    end
    end.

checkSAckReceptionBuffer(Direction = initiator, Ack, SEG_ACK, Syn_or_Fin, State) ->
    checkSAckReceptionBuffer(Direction, Ack, SEG_ACK, Syn_or_Fin, [], run, State);

checkSAckReceptionBuffer(Direction = responder, Ack, SEG_ACK, Syn_or_Fin, State) ->
    checkSAckReceptionBuffer(Direction, Ack, SEG_ACK, Syn_or_Fin, [], run, State).

checkSAckReceptionBuffer(Direction=initiator, Ack, SEG_ACK, Syn_or_Fin, Acc, restart, #state{} = State) ->
    error_logger:info_msg("Restarting: Package Direction ~p~n", [Direction]),
    checkSAckReceptionBuffer(Direction, Ack, SEG_ACK, Syn_or_Fin, [], run, State#state{initiator_sack_store = lists:reverse(Acc) ++ State#state.initiator_sack_store});

checkSAckReceptionBuffer(Direction=responder, Ack, SEG_ACK, Syn_or_Fin, Acc, restart, #state{} = State) ->
    rror_logger:info_msg("Restarting: Package Direction ~p~n", [Direction]),
    checkSAckReceptionBuffer(Direction, Ack, SEG_ACK, Syn_or_Fin, [], run, State#state{responder_sack_store = lists:reverse(Acc) ++ State#state.responder_sack_store});

checkSAckReceptionBuffer(_Direction=initiator, false = _Ack, _SEG_ACK, _Syn_or_Fin, _Acc, run, #state{} = State) ->
    error_logger:info_msg("Received: Package with Ack = false in Direction ~p~n", [_Direction]),
    State;

checkSAckReceptionBuffer(_Direction=responder, false = _Ack, _SEG_ACK, _Syn_or_Fin, _Acc, run, #state{} = State) ->
    error_logger:info_msg("Received: Package with Ack = false in Direction ~p~n", [_Direction]),
    State;

checkSAckReceptionBuffer(_Direction=initiator, true = _Ack, _SEG_ACK, _Syn_or_Fin, Acc, run, #state{initiator_sack_store = Initiator_sack_store} = State) when Initiator_sack_store == [] ->
    error_logger:info_msg("Received: Package with Ack = false in Direction ~p~n", [_Direction]),
    State#state{initiator_sack_store =lists:reverse(Acc)};

checkSAckReceptionBuffer(_Direction=responder, true = _Ack, _SEG_ACK, _Syn_or_Fin, Acc,run,  #state{responder_sack_store = Responder_sack_store} = State) when Responder_sack_store == [] ->
    error_logger:info_msg("Received: Package with Ack = false in Direction ~p~n", [_Direction]),
    State#state{responder_sack_store =lists:reverse(Acc)};

checkSAckReceptionBuffer(Direction=initiator, true = Ack, SEG_ACK, Syn_or_Fin, Acc, run, 
			 #state{initiator_RCV_NXT = RCV_NXT, initiator_sack_store = [{SEG_SEQ, Retransmission_Index, Payload_size, Payload}|SAck_store_Tail]} = State) ->

    Filter_binary_out_fun = fun({FunSEG_SEQ, FunRetransmission_Index, FunPayloadLength, _FunPayload}) -> {FunSEG_SEQ, FunSEG_SEQ + FunPayloadLength, FunRetransmission_Index, FunPayloadLength} end,
    Filtered_binary_out = lists:map(Filter_binary_out_fun, [{SEG_SEQ, Retransmission_Index, Payload_size, Payload}|SAck_store_Tail]),
    error_logger:info_msg("checkSAckReceptionBuffer: Bufferstate in Direction ~p has RCV_NXT:~p, SEG_ACK: ~p, Window: ~p and content: ~n~p~n", [Direction, RCV_NXT, SEG_ACK, calculate_window(reverse(Direction), State), Filtered_binary_out]),
    RCV_NXT32 = modulo32bit(RCV_NXT),
    SEG_SEQ32 = modulo32bit(SEG_SEQ),
    SEG_ACK32 = modulo32bit(SEG_ACK),
    %% test SEG_SEQ32 =< RCV_NXT32 =< SEG_ACK is not ever assured, the acknowledgement may not acknowlege the latest packet
    %% test SEG_SEQ32 =< RCV_NXT32
    %% test SEG_SEQ32 =< SEG_ACK =< RCV_NXT32 + Window
    case smaller_or_equal32(SEG_SEQ32, SEG_ACK32) of
	true -> % SEG_SEQ =< SEG_ACK
	    RCV_NXT_plus_Window32 = add_modulo_32bit(RCV_NXT32, calculate_window(reverse(Direction), State)),
	    case smaller_or_equal32(SEG_ACK32, RCV_NXT_plus_Window32) of
		true -> % SEG_ACK =< RCV_NXT + Window
		    Delta_overlap_ignore = add_modulo_32bit(RCV_NXT32, -SEG_SEQ32),
		    case Delta_overlap_ignore < Payload_size of
			true ->
			    Ack_payload_store = State#state.initiator_ack_payload_store,
			    %% Consider overlapping payload strategy
			    case State#state.overlapping_payload_strategy of
				last_wins ->
				    Ack_payload_store_size = byte_size(Ack_payload_store),
				    if 
					Ack_payload_store_size > Delta_overlap_ignore -> 
					    StateNew1 = State#state{initiator_ack_payload_store = <<Ack_payload_store:(Ack_payload_store_size - Delta_overlap_ignore)/binary, Payload/binary>>};
					true ->
					    <<_Ignore:Delta_overlap_ignore/binary, Payload_non_duplicate/binary>> = <<Payload/binary>>,
					    StateNew1 = State#state{initiator_ack_payload_store = <<Ack_payload_store/binary, Payload_non_duplicate/binary>>}
				    end;
				first_wins ->
				    <<_Ignore:Delta_overlap_ignore/binary, Payload_non_duplicate/binary>> = <<Payload/binary>>,
				    StateNew1 = State#state{initiator_ack_payload_store = <<Ack_payload_store/binary, Payload_non_duplicate/binary>>}
			    end,
			    StateNew2 = storeState_RCV_NXT(Direction, StateNew1, SEG_SEQ, Payload_size-Delta_overlap_ignore, _Syn_or_Fin_for_peer_direction = false),
			    StateNew  = StateNew2#state{initiator_sack_store = SAck_store_Tail},
			    checkSAckReceptionBuffer(Direction, Ack, SEG_ACK, Syn_or_Fin, Acc, restart, StateNew);
			false -> % package SEG_SEQ + payload length is smaller than RCV_NXT
			    %% drop packet from queue
                            error_logger:info_msg("checkSAckReceptionBuffer: Dropping from buffer in Direction ~p has RCV_NXT:~p, SEG_ACK: ~p, Window: ~p and content: ~n~p~n", [Direction, RCV_NXT, SEG_ACK, calculate_window(reverse(Direction), State), {SEG_SEQ, SEG_SEQ + Payload_size}]),
			    StateNew  = State#state{initiator_sack_store = SAck_store_Tail},
			    checkSAckReceptionBuffer(Direction, Ack, SEG_ACK, Syn_or_Fin, Acc, run, StateNew)
		    end;
		false -> % SEG_ACK > RCV_NXT + Window
		    %% Acknowledgement out of Window
	            error_logger:info_msg("checkSAckReceptionBuffer:Acknowledgement out of Window, Direction:~p, SEG_SEQ32:~p:~p ,Peer:SEG_ACK32:~p, RCV_NXT:~p, Window:~p~n", [Direction, SEG_SEQ32, SEG_SEQ32+Payload_size, SEG_ACK32, RCV_NXT, calculate_window(reverse(Direction), State)]),
		    State#state{initiator_sack_store = [{SEG_SEQ, Retransmission_Index, Payload_size, Payload}|SAck_store_Tail]}
	    end;
	false -> % SEG_ACK32 < SEG_SEQ32
            %% test SEG_SEQ32 =< RCV_NXT32 + Window
            RCV_NXT_plus_Window32 = add_modulo_32bit(RCV_NXT32, calculate_window(reverse(Direction), State)),
            case smaller_or_equal32(SEG_SEQ32, RCV_NXT_plus_Window32) of
		true -> % SEG_SEQ32 =< RCV_NXT + Window
		    %% keep in queue
		    StateNew  = State#state{initiator_sack_store = SAck_store_Tail}, 
              	    checkSAckReceptionBuffer(Direction, Ack, SEG_ACK, Syn_or_Fin, [{SEG_SEQ, Retransmission_Index, Payload_size, Payload}|Acc], run, StateNew);
		false -> % SEG_SEQ32 > RCV_NXT + Window
		    %% drop from queue
		    error_logger:info_msg("checkSAckReceptionBuffer: Dropping from buffer as SEG_SEQ32 > RCV_NXT + Window in Direction ~p has RCV_NXT:~p, SEG_ACK: ~p, Window: ~p and content: ~n~p~n", [Direction, RCV_NXT, SEG_ACK, calculate_window(reverse(Direction), State), {SEG_SEQ, SEG_SEQ + Payload_size}]),
		    StateNew  = State#state{initiator_sack_store = SAck_store_Tail}, 
		    checkSAckReceptionBuffer(Direction, Ack, SEG_ACK, Syn_or_Fin, Acc, run, StateNew)
	    end
    end;


checkSAckReceptionBuffer(Direction=responder, true = Ack, SEG_ACK, Syn_or_Fin, Acc, run, 
			 #state{responder_RCV_NXT = RCV_NXT, responder_sack_store = [{SEG_SEQ, Retransmission_Index, Payload_size, Payload}|SAck_store_Tail]} = State) ->

    Filter_binary_out_fun = fun({FunSEG_SEQ, FunRetransmission_Index, FunPayloadLength, _FunPayload}) -> {FunSEG_SEQ, FunSEG_SEQ + FunPayloadLength, FunRetransmission_Index, FunPayloadLength} end,
    Filtered_binary_out = lists:map(Filter_binary_out_fun, [{SEG_SEQ, Retransmission_Index, Payload_size, Payload}|SAck_store_Tail]),
    error_logger:info_msg("checkSAckReceptionBuffer: Bufferstate in Direction ~p has RCV_NXT:~p, SEG_ACK: ~p, Window: ~p and content: ~n~p~n", [Direction, RCV_NXT, SEG_ACK, calculate_window(reverse(Direction), State), Filtered_binary_out]),
    RCV_NXT32 = modulo32bit(RCV_NXT),
    SEG_SEQ32 = modulo32bit(SEG_SEQ),
    SEG_ACK32 = modulo32bit(SEG_ACK),
    %% test SEG_SEQ32 =< RCV_NXT32 =< SEG_ACK is not ever assured, the acknowledgement may not acknowlege the latest packet
    %% test SEG_SEQ32 =< RCV_NXT32
    %% test SEG_SEQ32 =< SEG_ACK =< RCV_NXT32 + Window
    case smaller_or_equal32(SEG_SEQ32, SEG_ACK32) of
	true -> % SEG_SEQ =< SEG_ACK
	    RCV_NXT_plus_Window32 = add_modulo_32bit(RCV_NXT32, calculate_window(reverse(Direction), State)),
	    case smaller_or_equal32(SEG_ACK32, RCV_NXT_plus_Window32) of
		true -> % SEG_ACK =< RCV_NXT + Window
		    Delta_overlap_ignore = add_modulo_32bit(RCV_NXT32, -SEG_SEQ32),
		    case Delta_overlap_ignore < Payload_size of
			true ->
			    Ack_payload_store = State#state.responder_ack_payload_store,
			    %% Consider overlapping payload strategy
			    case State#state.overlapping_payload_strategy of
				last_wins ->
				    Ack_payload_store_size = byte_size(Ack_payload_store),
				    if 
					Ack_payload_store_size > Delta_overlap_ignore -> 
					    StateNew1 = State#state{responder_ack_payload_store = <<Ack_payload_store:(Ack_payload_store_size - Delta_overlap_ignore)/binary, Payload/binary>>};
					true ->
					    <<_Ignore:Delta_overlap_ignore/binary, Payload_non_duplicate/binary>> = <<Payload/binary>>,
					    StateNew1 = State#state{responder_ack_payload_store = <<Ack_payload_store/binary, Payload_non_duplicate/binary>>}
				    end;
				first_wins ->
				    <<_Ignore:Delta_overlap_ignore/binary, Payload_non_duplicate/binary>> = <<Payload/binary>>,
				    StateNew1 = State#state{responder_ack_payload_store = <<Ack_payload_store/binary, Payload_non_duplicate/binary>>}
			    end,
			    StateNew2 = storeState_RCV_NXT(Direction, StateNew1, SEG_SEQ, Payload_size-Delta_overlap_ignore, _Syn_or_Fin_for_peer_direction = false),
			    StateNew  = StateNew2#state{responder_sack_store = SAck_store_Tail},
			    checkSAckReceptionBuffer(Direction, Ack, SEG_ACK, Syn_or_Fin, Acc, restart, StateNew);
			false -> % package SEG_SEQ + payload length is smaller than RCV_NXT
			    %% drop packet from queue
                            error_logger:info_msg("checkSAckReceptionBuffer: Dropping from buffer in Direction ~p has RCV_NXT:~p, SEG_ACK: ~p, Window: ~p and content: ~n~p~n", [Direction, RCV_NXT, SEG_ACK, calculate_window(reverse(Direction), State), {SEG_SEQ, SEG_SEQ + Payload_size}]),
			    StateNew  = State#state{responder_sack_store = SAck_store_Tail},
			    checkSAckReceptionBuffer(Direction, Ack, SEG_ACK, Syn_or_Fin, Acc, run, StateNew)
		    end;
		false -> % SEG_ACK > RCV_NXT + Window
		    %% Acknowledgement out of Window
	            error_logger:info_msg("checkSAckReceptionBuffer:Acknowledgement out of Window, Direction:~p, SEG_SEQ32:~p:~p ,Peer:SEG_ACK32:~p, RCV_NXT:~p, Window:~p~n", [Direction, SEG_SEQ32, SEG_SEQ32+Payload_size, SEG_ACK32, RCV_NXT, calculate_window(reverse(Direction), State)]),
		    State#state{responder_sack_store = [{SEG_SEQ, Retransmission_Index, Payload_size, Payload}|SAck_store_Tail]}
	    end;
	false -> % SEG_ACK32 < SEG_SEQ32
            %% test SEG_SEQ32 =< RCV_NXT32 + Window
            RCV_NXT_plus_Window32 = add_modulo_32bit(RCV_NXT32, calculate_window(reverse(Direction), State)),
            case smaller_or_equal32(SEG_SEQ32, RCV_NXT_plus_Window32) of
		true -> % SEG_SEQ32 =< RCV_NXT + Window
		    %% keep in queue
		    StateNew  = State#state{responder_sack_store = SAck_store_Tail}, 
              	    checkSAckReceptionBuffer(Direction, Ack, SEG_ACK, Syn_or_Fin, [{SEG_SEQ, Retransmission_Index, Payload_size, Payload}|Acc], run, StateNew);
		false -> % SEG_SEQ32 > RCV_NXT + Window
		    %% drop from queue
		    error_logger:info_msg("checkSAckReceptionBuffer: Dropping from buffer as SEG_SEQ32 > RCV_NXT + Window in Direction ~p has RCV_NXT:~p, SEG_ACK: ~p, Window: ~p and content: ~n~p~n", [Direction, RCV_NXT, SEG_ACK, calculate_window(reverse(Direction), State), {SEG_SEQ, SEG_SEQ + Payload_size}]),
		    StateNew  = State#state{responder_sack_store = SAck_store_Tail}, 
		    checkSAckReceptionBuffer(Direction, Ack, SEG_ACK, Syn_or_Fin, Acc, run, StateNew)
	    end
    end.                 

storeState_SACK_PERMITTED(_Direction=initiator, State) ->
    State#state{initiator_sack_permitted = true};

storeState_SACK_PERMITTED(_Direction=responder, State) ->
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



reverse(initiator) ->
    responder;
reverse(responder) ->
    initiator.


%% State handling:

%% Syn (when Ack received before)
handle_syn_ack_response_syn(Current_state_name, New_state_name, {Direction, _IP, TCP, Decoded}, State) ->
    case test_sequence_no_in_window(Direction, State, TCP#tcp.seqno) of
	true ->
            StateNew0 = ?DEBUG_LOG({{?current_function_name(), Current_state_name, New_state_name, syn_in_sequence}, lists:keyfind(window_scale, 1, Decoded#decoded.opt_decoded)}, Direction, _IP, TCP, Decoded, State),
	    StateNew1 = storeState_RCV_NXT(Direction, StateNew0, TCP#tcp.seqno, (TCP#tcp.syn =:= 1) or (TCP#tcp.fin =:=1)),
	    StateNew2 = storeState_SND_UNA(Direction, StateNew1, TCP#tcp.ackno, (TCP#tcp.ack =:= 1)),
	    StateNew3 = storeState_SND_WND(Direction, StateNew2, TCP#tcp.win),
            case lists:keyfind(window_scale, 1, Decoded#decoded.opt_decoded) of
		{window_scale, ShiftCount} ->
                    StateNew4 = storeState_SND_WND_SCALE(Direction, StateNew3, ShiftCount);
                false ->
                    StateNew4 = StateNew3 % responder_RCV_WND_SCALE remains undefined
            end,
            case lists:keyfind(sack_permitted, 1, Decoded#decoded.opt_decoded) of
		{sack_permitted, true} ->
                    StateNew  = storeState_SACK_PERMITTED(Direction, StateNew4);
                false ->
                    StateNew  = StateNew4 % responder_sack_permitted remains undefined
            end,
	    NextStateName = New_state_name;
	false ->
            StateNew0 = ?DEBUG_LOG({{?current_function_name(), Current_state_name, Current_state_name, syn_out_of_sequence}, lists:keyfind(window_scale, 1, Decoded#decoded.opt_decoded)}, Direction, _IP, TCP, Decoded, State),
	    StateNew  = StateNew0,
	    NextStateName = Current_state_name
    end,
    {ok, Timeout} = set_timeout(NextStateName),
    {ok, NextStateName, Timeout, StateNew}.

handle_syn_response_ack(Current_state_name, New_state_name, {Direction, _IP, TCP, Decoded}, State) ->
    case stack_member(add_modulo_32bit((TCP#tcp.ack =:= 1), -1), State#state.initiator_syn_seg_seq_stack) of
	true ->
            StateNew0 = ?DEBUG_LOG({{?current_function_name(), Current_state_name, New_state_name, ack_in_sequence}, lists:keyfind(window_scale, 1, Decoded#decoded.opt_decoded)}, Direction, _IP, TCP, Decoded, State),
            Payload = Decoded#decoded.payload,
            Payload_size = Decoded#decoded.payload_size,
	    StateNew1 = storeState_RCV_NXT(reverse(Direction), StateNew0, add_modulo_32bit(TCP#tcp.ackno, -1), (TCP#tcp.syn =:= 1) or (TCP#tcp.fin =:=1)), % initialize initiator
            StateNew2 = StateNew1#state{syn_ack_received = true},     % set flag for received Ack
	    StateNew3 = storeState_Payload(Direction, StateNew2, TCP#tcp.seqno, Payload_size, <<Payload:Payload_size/binary>>),
	    StateNew4 = checkPayloadReceptionBuffer(reverse(Direction), (TCP#tcp.ack =:= 1), TCP#tcp.ackno, (TCP#tcp.syn =:= 1) or (TCP#tcp.fin =:=1), StateNew3),
	    StateNew5 = checkSAckReceptionBuffer(reverse(Direction), (TCP#tcp.ack =:= 1), TCP#tcp.ackno, (TCP#tcp.syn =:= 1) or (TCP#tcp.fin =:=1), StateNew4),
	    StateNew6 = storeState_SND_UNA(Direction, StateNew5, TCP#tcp.ackno, (TCP#tcp.ack =:= 1)),
	    StateNew7 = storeState_SND_WND(Direction, StateNew6, TCP#tcp.win),
	    StateNew8 = storeState_RCV_NXT(Direction, StateNew7, TCP#tcp.seqno, (TCP#tcp.syn =:= 1) or (TCP#tcp.fin =:=1)),
	    StateNew  = forward_stream_ack_payload_store(Direction, TCP#tcp.fin, {Decoded#decoded.source_address, TCP#tcp.sport}, {Decoded#decoded.destination_address, TCP#tcp.dport}, StateNew8),
            NextStateName = New_state_name;
	false ->
            StateNew0 = ?DEBUG_LOG({{?current_function_name(), Current_state_name, Current_state_name, ack_out_of_sequence}, lists:keyfind(window_scale, 1, Decoded#decoded.opt_decoded)}, Direction, _IP, TCP, Decoded, State),
	    StateNew  = StateNew0,
	    NextStateName = Current_state_name
    end,
    {ok, Timeout} = set_timeout(NextStateName),
    {ok, NextStateName, Timeout, StateNew}.

handle_syn_repetition(Current_state_name, {Direction, _IP, TCP, Decoded}, State) ->
    StateNew0 = ?DEBUG_LOG({{?current_function_name(), Current_state_name, Current_state_name, syn_repeated}, lists:keyfind(window_scale, 1, Decoded#decoded.opt_decoded)}, Direction, _IP, TCP, Decoded, State),
    StateNew1 = storeState_SND_UNA(Direction, StateNew0, TCP#tcp.ackno, (TCP#tcp.ack =:= 1)),
    StateNew2 = storeState_SND_WND(Direction, StateNew1, TCP#tcp.win),
    case lists:keyfind(window_scale, 1, Decoded#decoded.opt_decoded) of
	{window_scale, ShiftCount} ->
	    StateNew3 = storeState_SND_WND_SCALE(Direction, StateNew2, ShiftCount);
        false ->
	    StateNew3 = StateNew2 % initiator_RCV_WND_SCALE remains undefined
    end,
    case lists:keyfind(sack_permitted, 1, Decoded#decoded.opt_decoded) of
	{sack_permitted, true} ->
	    StateNew4 = storeState_SACK_PERMITTED(Direction, StateNew3);
        false ->
	    StateNew4 = StateNew3 % initiator_sack_permitted remains undefined
    end,
    StateNew  = StateNew4#state{initiator_syn_seg_seq_stack = stack_element(TCP#tcp.seqno, StateNew4#state.initiator_syn_seg_seq_stack)},
    NextStateName = Current_state_name,
    {ok, Timeout} = set_timeout(NextStateName),
    {ok, NextStateName, Timeout, StateNew}.


handle_syn_response_synack(Current_state_name, New_state_name, {Direction, _IP, TCP, Decoded}, State) ->
    case stack_member(add_modulo_32bit(TCP#tcp.ackno, -1), State#state.initiator_syn_seg_seq_stack) of
	true ->
            StateNew0 = ?DEBUG_LOG({{?current_function_name(), Current_state_name, New_state_name, synack_in_sequence}, lists:keyfind(window_scale, 1, Decoded#decoded.opt_decoded)}, Direction, _IP, TCP, Decoded, State),
            StateNew1 = storeState_RCV_NXT(reverse(Direction), StateNew0, add_modulo_32bit(TCP#tcp.ackno, -1), true), % initialize initiator
	    StateNew2 = storeState_RCV_NXT(Direction, StateNew1, TCP#tcp.seqno, (TCP#tcp.syn =:= 1) or (TCP#tcp.fin =:=1)),
	    StateNew3 = storeState_SND_UNA(Direction, StateNew2, TCP#tcp.ackno, (TCP#tcp.ack =:= 1)),
	    StateNew4 = storeState_SND_WND(Direction, StateNew3, TCP#tcp.win),
            case lists:keyfind(window_scale, 1, Decoded#decoded.opt_decoded) of
		{window_scale, ShiftCount} ->
                    StateNew5 = storeState_SND_WND_SCALE(Direction, StateNew4, ShiftCount);
                false ->
                    StateNew5 = StateNew4 % responder_RCV_WND_SCALE remains undefined
            end,
            case lists:keyfind(sack_permitted, 1, Decoded#decoded.opt_decoded) of
		{sack_permitted, true} ->
                    StateNew  = storeState_SACK_PERMITTED(Direction, StateNew5);
                false ->
                    StateNew  = StateNew5 % responder_sack_permitted remains undefined
            end,
	    NextStateName = New_state_name;
	false ->
            StateNew0 = ?DEBUG_LOG({{?current_function_name(), Current_state_name, Current_state_name, synack_out_of_sequence}, lists:keyfind(window_scale, 1, Decoded#decoded.opt_decoded)}, Direction, _IP, TCP, Decoded, State),
	    StateNew  = StateNew0,
	    NextStateName = Current_state_name
    end,
    {ok, Timeout} = set_timeout(NextStateName),
    {ok, NextStateName, Timeout, StateNew}.

%% Note: Here below sequence number has to be checked before accepting the reset.!!!!!

handle_initial_syn_or_syn_after_reset(Current_state_name, New_state_name, {Direction, _IP, TCP, Decoded}, State) ->
    StateNew0 = ?DEBUG_LOG({{?current_function_name(), Current_state_name, New_state_name, syn_reception_from_initiator}, lists:keyfind(window_scale, 1, Decoded#decoded.opt_decoded)}, Direction, _IP, TCP, Decoded, State),
    StateNew1 = storeState_SND_UNA(Direction, StateNew0, TCP#tcp.ackno, (TCP#tcp.ack =:= 1)),
    StateNew2 = storeState_SND_WND(Direction, StateNew1, TCP#tcp.win),
    case lists:keyfind(window_scale, 1, Decoded#decoded.opt_decoded) of
	{window_scale, ShiftCount} ->
	    StateNew3 = storeState_SND_WND_SCALE(Direction, StateNew2, ShiftCount);
	false ->
	    StateNew3 = StateNew2 % initiator_RCV_WND_SCALE remains undefined
    end,
    case lists:keyfind(sack_permitted, 1, Decoded#decoded.opt_decoded) of
	{sack_permitted, true} ->
	    StateNew4 = storeState_SACK_PERMITTED(Direction,StateNew3);
	false ->
	    StateNew4 = StateNew3 % initiator_sack_permitted remains undefined
    end,
    StateNew  = StateNew4#state{initiator_syn_seg_seq_stack = stack_element(TCP#tcp.seqno, stack_new(?MaxNumberOfSynSegSeqOnStack))}, % clear stack due to reset!!
    NextStateName = New_state_name, 
    {ok, Timeout} = set_timeout(NextStateName),
    {ok, Timeout, StateNew}.

handle_payload(Current_state_name, New_state_name, {Direction, _IP, TCP, Decoded}, State) -> % payload, Note: if ack == 0, seqno should be 0
    Source = {Decoded#decoded.source_address, TCP#tcp.sport},    
    Destination = {Decoded#decoded.destination_address, TCP#tcp.dport}, 
    Payload_size = Decoded#decoded.payload_size,
    case test_sequence_no_in_window(Direction, State, TCP#tcp.seqno, Payload_size) of
	true ->
            Payload = Decoded#decoded.payload,
            StateNew0 = ?DEBUG_LOG({{?current_function_name(), Current_state_name, New_state_name, data_in_sequence}, lists:keyfind(window_scale, 1, Decoded#decoded.opt_decoded)}, Direction, _IP, TCP, Decoded, State),
	    StateNew1 = storeState_Payload(Direction, StateNew0, TCP#tcp.seqno, Payload_size, <<Payload:Payload_size/binary>>),
	    StateNew2 = checkPayloadReceptionBuffer(reverse(Direction), (TCP#tcp.ack =:= 1), TCP#tcp.ackno, (TCP#tcp.syn =:= 1) or (TCP#tcp.fin =:=1), StateNew1),
	    StateNew3 = checkSAckReceptionBuffer(reverse(Direction), (TCP#tcp.ack =:= 1), TCP#tcp.ackno, (TCP#tcp.syn =:= 1) or (TCP#tcp.fin =:=1), StateNew2),
	    StateNew4 = storeState_SND_UNA(Direction, StateNew3, TCP#tcp.ackno, (TCP#tcp.ack =:= 1)),
	    StateNew5 = storeState_SND_WND(Direction, StateNew4, TCP#tcp.win),
	    StateNew6 = storeState_RCV_NXT(Direction, StateNew5, TCP#tcp.seqno, (TCP#tcp.syn =:= 1) or (TCP#tcp.fin =:=1)),
	    StateNew  = forward_stream_ack_payload_store(Direction, (TCP#tcp.fin =:=1), Source, Destination, StateNew6),
            NextStateName = New_state_name;
        false ->
            StateNew0 = ?DEBUG_LOG({{?current_function_name(), Current_state_name, Current_state_name, data_out_of_sequence}, lists:keyfind(window_scale, 1, Decoded#decoded.opt_decoded)}, Direction, _IP, TCP, Decoded, State),
	    error_logger:warning_msg("Warning!!!! Direction:~w, SEG_SEQ: ~w, Payload_size ~w, RCV_NXT: ~w, RCV_WND: ~w~n", [Direction, TCP#tcp.seqno, Decoded#decoded.payload_size, State#state.initiator_RCV_NXT, calculate_window(Direction, State)]),
            NextStateName = Current_state_name,
	    StateNew  = StateNew0
    end, 
    {ok, Timeout} = set_timeout(NextStateName),
    {ok, NextStateName, Timeout, StateNew}.


handle_reset(Current_state_name, New_state_name, {Direction, _IP, TCP, Decoded}, State) -> % payload, Note: if ack == 0, seqno should be 0
    Payload_size = Decoded#decoded.payload_size,    
    case test_sequence_no_in_window(Direction, State, TCP#tcp.seqno, Payload_size) of
	true ->
            StateNew0 = ?DEBUG_LOG({{?current_function_name(), Current_state_name, New_state_name, reset_in_sequence}, lists:keyfind(window_scale, 1, Decoded#decoded.opt_decoded)}, Direction, _IP, TCP, Decoded, State),
            StateNew1  = StateNew0#state{initiator_syn_seg_seq_stack = stack_element(TCP#tcp.seqno, stack_new(?MaxNumberOfSynSegSeqOnStack))}, % clear stack due to reset!!
            Timeout = infinity, 
            NextStateName = New_state_name,
            StateNew  = StateNew1;
        false ->
            StateNew0 = ?DEBUG_LOG({{?current_function_name(), Current_state_name, Current_state_name, reset_out_of_sequence}, lists:keyfind(window_scale, 1, Decoded#decoded.opt_decoded)}, Direction, _IP, TCP, Decoded, State),
	    error_logger:warning_msg("Warning!!!! Direction:~w, SEG_SEQ: ~w, Payload_size ~w, RCV_NXT: ~w, RCV_WND: ~w~n", [Direction, TCP#tcp.seqno, Decoded#decoded.payload_size, State#state.initiator_RCV_NXT, calculate_window(Direction, State)]),
            Timeout = infinity,
            NextStateName = Current_state_name,
	    StateNew  = StateNew0
    end, 
    {ok, NextStateName, Timeout, StateNew}.

handle_retransmission(Current_state_name, {Direction, _IP, TCP, Decoded}, State) -> % payload, Note: if ack == 0, seqno should be 0
    Payload_size = Decoded#decoded.payload_size,
    case test_sequence_no_in_window(Direction, State, TCP#tcp.seqno, Payload_size) of
	true ->
            StateNew0 = ?DEBUG_LOG({{?current_function_name(), Current_state_name, Current_state_name, retransmission_in_sequence}, lists:keyfind(window_scale, 1, Decoded#decoded.opt_decoded)}, Direction, _IP, TCP, Decoded, State),
	    StateNew  = StateNew0;
        false ->
            StateNew0 = ?DEBUG_LOG({{?current_function_name(), Current_state_name, Current_state_name, retransmission_out_of_sequence}, lists:keyfind(window_scale, 1, Decoded#decoded.opt_decoded)}, Direction, _IP, TCP, Decoded, State),
	    error_logger:warning_msg("Warning!!!! Direction:~w, SEG_SEQ: ~w, Payload_size ~w, RCV_NXT: ~w, RCV_WND: ~w~n", [Direction, TCP#tcp.seqno, Decoded#decoded.payload_size, State#state.initiator_RCV_NXT, calculate_window(Direction, State)]),
	    StateNew  = StateNew0
    end, 
    NextStateName = Current_state_name,
    {ok, Timeout} = set_timeout(NextStateName),    
    {ok, Timeout, StateNew}.

handle_initial_fin(Current_state_name, New_state_name, {Direction, _IP, TCP, Decoded}, State) ->
    %% same as handle payload, but sets close_initiator
    Source = {Decoded#decoded.source_address, TCP#tcp.sport},    
    Destination = {Decoded#decoded.destination_address, TCP#tcp.dport}, 
    Payload_size = Decoded#decoded.payload_size,
    case test_sequence_no_in_window(Direction, State, TCP#tcp.seqno, Payload_size) of
	true ->
            Payload = Decoded#decoded.payload,
            StateNew0 = ?DEBUG_LOG({{?current_function_name(), Current_state_name, New_state_name, data_in_sequence}, lists:keyfind(window_scale, 1, Decoded#decoded.opt_decoded)}, Direction, _IP, TCP, Decoded, State),
	    StateNew1 = storeState_Payload(Direction, StateNew0, TCP#tcp.seqno, Payload_size, <<Payload:Payload_size/binary>>),
	    StateNew2 = checkPayloadReceptionBuffer(reverse(Direction), (TCP#tcp.ack =:= 1), TCP#tcp.ackno, (TCP#tcp.syn =:= 1) or (TCP#tcp.fin =:=1), StateNew1),
	    StateNew3 = checkSAckReceptionBuffer(reverse(Direction), (TCP#tcp.ack =:= 1), TCP#tcp.ackno, (TCP#tcp.syn =:= 1) or (TCP#tcp.fin =:=1), StateNew2),
	    StateNew4 = storeState_SND_UNA(Direction, StateNew3, TCP#tcp.ackno, (TCP#tcp.ack =:= 1)),
	    StateNew5 = storeState_SND_WND(Direction, StateNew4, TCP#tcp.win),
	    StateNew6 = storeState_RCV_NXT(Direction, StateNew5, TCP#tcp.seqno, (TCP#tcp.syn =:= 1) or (TCP#tcp.fin =:=1)),
	    StateNew7 = forward_stream_ack_payload_store(Direction, (TCP#tcp.fin =:=1), Source, Destination, StateNew6),
            NextStateName = New_state_name;
        false ->
            StateNew0 = ?DEBUG_LOG({{?current_function_name(), Current_state_name, Current_state_name, data_out_of_sequence}, lists:keyfind(window_scale, 1, Decoded#decoded.opt_decoded)}, Direction, _IP, TCP, Decoded, State),
	    error_logger:warning_msg("Warning!!!! Direction:~w, SEG_SEQ: ~w, Payload_size ~w, RCV_NXT: ~w, RCV_WND: ~w~n", [Direction, TCP#tcp.seqno, Decoded#decoded.payload_size, State#state.initiator_RCV_NXT, calculate_window(Direction, State)]),
            NextStateName = Current_state_name,
            StateNew7  = StateNew0
    end, 
    StateNew = set_close_initiator(Direction, StateNew7),
    {ok, Timeout} = set_timeout(NextStateName),
    {ok, NextStateName, Timeout, StateNew}.

handle_ignore(Current_state_name, {Direction, _IP, TCP, Decoded}, State) -> % payload, Note: if ack == 0, seqno should be 0
    Payload_size = Decoded#decoded.payload_size,
    case test_sequence_no_in_window(Direction, State, TCP#tcp.seqno, Payload_size) of
	true ->
            StateNew0 = ?DEBUG_LOG({{?current_function_name(), Current_state_name, Current_state_name, ignore_in_sequence}, lists:keyfind(window_scale, 1, Decoded#decoded.opt_decoded)}, Direction, _IP, TCP, Decoded, State),
	    StateNew  = StateNew0;
        false ->
            StateNew0 = ?DEBUG_LOG({{?current_function_name(), Current_state_name, Current_state_name, ignore_out_of_sequence}, lists:keyfind(window_scale, 1, Decoded#decoded.opt_decoded)}, Direction, _IP, TCP, Decoded, State),
	    error_logger:warning_msg("Warning!!!! Direction:~w, SEG_SEQ: ~w, Payload_size ~w, RCV_NXT: ~w, RCV_WND: ~w~n", [Direction, TCP#tcp.seqno, Decoded#decoded.payload_size, State#state.initiator_RCV_NXT, calculate_window(Direction, State)]),
	    StateNew  = StateNew0
    end, 
    NextStateName = Current_state_name,
    {ok, Timeout} = set_timeout(NextStateName),
    {ok, Timeout, StateNew}.

set_timeout(State_name) ->
    Timeout = case State_name == state_time_wait of
		  true ->
		      10000;
		  false ->
		      infinity
	      end, 
    {ok, Timeout}.



