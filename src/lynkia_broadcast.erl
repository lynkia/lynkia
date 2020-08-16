%% -------------------------------------------------------------------
%%
%% Copyright (c) 2018 Christopher S. Meiklejohn.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------
%%%-----------------------------------------------------------------------------
%%% @doc Broadcast messages via Partisan.
%%% @end
%%%-----------------------------------------------------------------------------

-module(lynkia_broadcast).

-author("Christopher S. Meiklejohn <christopher.meiklejohn@gmail.com>").

%% API
-export([start_link/0,
         stop/0,
         broadcast/2,
         update/1,
         debug/0]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-record(state, {
    next_id :: integer(),
    membership :: list(),
    pid :: identifier()
}).

%%%===================================================================
%%% API
%%%===================================================================

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

stop() ->
    gen_server:stop(?MODULE).

%% @doc Broadcast a new message to the given server ref
broadcast(ServerRef, Message) ->
    gen_server:cast(?MODULE, {broadcast, ServerRef, Message}).

%% @doc Membership update.
update(LocalState0) ->
    LocalState = partisan_peer_service:decode(LocalState0),
    gen_server:cast(?MODULE, {update, LocalState}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%% @private
init([]) ->
    %% Seed the random number generator.
    partisan_config:seed(),

    %% Register membership update callback.
    partisan_peer_service:add_sup_callback(fun ?MODULE:update/1),

    %% Open ETS table to track received messages.
    ?MODULE = ets:new(?MODULE, [set, named_table, public]),

    %% Start with initial membership.
    {ok, Membership} = partisan_peer_service:members(),
    io:format("Starting with membership: ~p~n", [Membership]),

    {ok, #state{
        next_id = 0,
        membership = membership(Membership),
        pid = erlang:spawn(fun() -> ok end)
    }}.

%% @private
handle_call(Msg, _From, State) ->
    io:format("Unhandled call messages at module ~p: ~p~n", [?MODULE, Msg]),
    {reply, ok, State}.

%% @private
handle_cast({broadcast, ServerRef, Message}, #state{next_id = NextId, membership = Membership} = State) ->
    S1 = schedule_gc(State),
    %% Generate message id.
    Myself = lynkia_utils:myself(),
    Key = {Myself, NextId, erlang:phash2(Message)},
    Value = lynkia_utils:now(),

    %% Store outgoing message.
    true = ets:insert(?MODULE, {Key, Value}),

    %% Forward to random subset of peers.
    Fanout = lynkia_config:get(fanout),
    AntiEntropyMembers = select_random_sublist(membership(Membership), Fanout),
    lists:foreach(fun(N) ->
        Manager = partisan_pluggable_peer_service_manager,
        Term = {broadcast, Key, ServerRef, Message, Myself},
        Manager:forward_message(N, undefined, ?MODULE, Term, [])
    end, AntiEntropyMembers -- [Myself]),

    {noreply, S1#state{next_id = NextId + 1}};

handle_cast({update, Membership0}, State) ->
    Membership = membership(Membership0),
    {noreply, State#state{membership = Membership}};

handle_cast(gc, State) ->
    case is_table_empty(?MODULE) of
        true ->
            {noreply, State};
        false ->
            TTL = lynkia_config:get(broadcast_ets_ttl),
            Now = lynkia_utils:now() - TTL,
            ets:select_delete(?MODULE, [{
                {'$1', '$2'},
                [{'=<', '$2', Now}],
                [true]
            }]),
            S1 = schedule_gc(State),
            {noreply, S1}
    end;

handle_cast(Msg, State) ->
    io:format("Unhandled cast messages at module ~p: ~p~n", [?MODULE, Msg]),
    {noreply, State}.

%% @private
%% Incoming messages.
handle_info({broadcast, Key, ServerRef, Message, FromNode}, #state{membership = Membership} = State) ->
    S1 = schedule_gc(State),
    case ets:lookup(?MODULE, Key) of
        [] ->
            %% Forward to process.
            partisan_util:process_forward(ServerRef, Message),

            %% Store.
            Value = lynkia_utils:now(),
            true = ets:insert(?MODULE, {Key, Value}),

            %% Forward to our peers.
            Myself = lynkia_utils:myself(),

            %% Forward to random subset of peers: except ourselves and where we got it from.
            Fanout = lynkia_config:get(fanout),
            AntiEntropyMembers = select_random_sublist(membership(Membership), Fanout),

            lists:foreach(fun(N) ->
                Manager = partisan_pluggable_peer_service_manager,
                Term = {broadcast, Key, ServerRef, Message, Myself},
                Manager:forward_message(N, undefined, ?MODULE, Term, [])
            end, AntiEntropyMembers -- [Myself, FromNode]),

            ok;
        _ ->
            ok
    end,
    {noreply, S1};

handle_info(_Msg, State) ->
    {noreply, State}.

%% @private
terminate(_Reason, _State) ->
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

%% @private -- sort to remove nondeterminism in node selection.
membership(Membership) ->
    lists:usort(Membership).

%% @private
select_random_sublist(Membership, K) ->
    Result = lists:sublist(shuffle(Membership), K),
    % io:format("random draw at node ~p was ~p~n", [node(), Result]),
    Result.

%% reference http://stackoverflow.com/questions/8817171/shuffling-elements-in-a-list-randomly-re-arrange-list-elements/8820501#8820501
shuffle(L) ->
    [X || {_, X} <- lists:sort([{rand:uniform(), N} || N <- L])].

is_table_empty(Table) ->
    case ets:first(Table) of
        '$end_of_table' -> true;
        _ -> false
    end.

%% @doc
schedule_gc(State) ->
    case State of #state{ pid = Timer } ->
        case erlang:is_process_alive(Timer) of
            true -> State;
            false ->
                State#state{
                    pid = erlang:spawn(fun() ->
                        Delay = lynkia_config:get(broadcast_ets_gc_interval),
                        timer:sleep(Delay),
                        gen_server:cast(?MODULE, gc)
                    end)
                }
        end
    end.

%% @doc
debug() ->
    ets:i(?MODULE).