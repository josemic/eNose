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
-module(defrag_root_sup).

-behaviour(supervisor).
%% API
-export([start_link/0, start_worker/3, stop_worker/1]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%%===================================================================
%%% API functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the supervisor
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

start_worker(Instance, {packet_with_addressing, {Ack, Syn, Fin, Rst, Seqno, Ackno, Win, Opt}, 
			{{Initiator_address, Initiator_port}, {Responder_address, Responder_port}}, 
			DLT, Time, Len, Packet, PayloadLength}, ChildWorkerList) ->
    Instance_s = integer_to_list(Instance),
    Ref_s = erlang:ref_to_list(make_ref()),                       
    %% Ref_s makes the instance unique after restart
    %% as instance starts again at 0
    Name_s = ?MODULE_STRING ++ "_" ++ Instance_s ++ "_" ++ Ref_s,  
    Name = list_to_atom (Name_s),
    %% the name must be a unique atom
    Defrag_worker = {Name, {defrag_worker, start_link, [Instance, {packet_with_addressing, {Ack, Syn, Fin, Rst, Seqno, Ackno, Win, Opt}, 
								   {{Initiator_address, Initiator_port}, {Responder_address, Responder_port}}, 
								   DLT, Time, Len, Packet, PayloadLength},ChildWorkerList]},
		     temporary, 2000, worker, [defrag_worker]},
    {ok, Result} = supervisor:start_child(?SERVER, Defrag_worker),
    io:format("Supervisor ~p start result: ~p~n", [?SERVER, Result]), 
    {ok, Result}.

stop_worker(ConnectionWorkerPid) ->
    %%Result = supervisor:terminate_child(?SERVER, WorkerPid), 
    %%io:format("Supervisor stopping Pid ~p with result~p~n", [WorkerPid, Result]), 
    %%Result.
    defrag_worker:stop(ConnectionWorkerPid).
%%gen_server:call(WorkerPid, stop_worker).

%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a supervisor is started using supervisor:start_link/[2,3],
%% this function is called by the new process to find out about
%% restart strategy, maximum restart frequency and child
%% specifications.
%%
%% @spec init(Args) -> {ok, {SupFlags, [ChildSpec]}} |
%%                     ignore |
%%                     {error, Reason}
%% @end
%%--------------------------------------------------------------------
init([]) ->
    RestartStrategy = one_for_one,
    MaxRestarts = 10,
    MaxSecondsBetweenRestarts = 60,

    SupFlags = {RestartStrategy, MaxRestarts, MaxSecondsBetweenRestarts},
    Defrag_server = {{local, defrag_server}, {defrag_server, start_link, []},
		     permanent, 2000, worker, [defrag_server]},

    {ok, {SupFlags, [Defrag_server]}}.
%%%===================================================================
%%% Internal functions
%%%===================================================================
