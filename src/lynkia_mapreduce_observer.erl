%%%-------------------------------------------------------------------
%% @doc This module contains the logic of the observer.
%% @author Julien Banken and Nicolas Xanthos
%% @end
%%%-------------------------------------------------------------------
-module(lynkia_mapreduce_observer).
-include("lynkia.hrl").

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

% API:

-export([
    start/2
]).

-record(state, {
    timer :: identifier(),
    data :: list()
}).

%% @doc Start an observer
%% Round - Number of the round
%% Pairs - Input pairs
%% Reduce - Reduce function
%% Options - Options
%% Propagate - Function to propagate the messages
start([_Round, _Pairs, _Reduce, _Options] = Data, Propagate) ->
    % Myself = lynkia_utils:myself(),
    % logger:info("[MAPREDUCE]: node=~p;type=~p;round=~p", [Myself, "observer", Round]),
    State = init(Data),
    listen(State, Propagate).

%% @doc Initialize the state of the observer
init([_Round, _Pairs, _Reduce, _Options] = Data) -> 
    Self = self(),
    Timer = set_timeout(fun()->
        Self ! continue
    end, [], get_delay()),
    #state{
        timer = Timer,
        data = Data
    }.

%% @doc Loop function that receives the incoming messages.
%% The function will process the messages sent by the other nodes.
%% When the node does not receive any messages from the leader, the node become leader.
listen(State, Propagate) ->
    receive
        {notify, NewRound, NewPairs} ->
            % When the master passes a new round.
            case State of #state{
                timer = Timer,
                data = [Round, _Pairs, Reduce, Options]
            } when NewRound > Round ->
                % Myself = lynkia_utils:myself(),
                % logger:info("[MAPREDUCE]: node=~p;type=~p;round=~p", [Myself, "observer", NewRound]),
                listen(State#state{
                    timer = restart_timer(Timer),
                    data = [NewRound, NewPairs, Reduce, Options]
                }, Propagate);
            _ ->
                listen(State, Propagate)
            end;
        continue ->
            % When the observer timeout, it becomes a master.
            case State of #state{timer = Timer, data = Data} ->
                clear_timeout(Timer),
                lynkia_mapreduce_leader:start(Data, Propagate)
            end;
        heartbeat ->
            % When the observer receives a heartbeat, the observer reset its timer.
            case State of #state{timer = Timer} ->
                listen(State#state{
                    timer = restart_timer(Timer)
                }, Propagate)
            end;
        stop ->
            io:format("Observer - Stop~n"),
            % Myself = lynkia_utils:myself(),
            % logger:info("[STOP-MAPREDUCE]: node=~p;type=~p;message=~p", [Myself, "observer", "stop"]),
            % When another master returns a result, the observer is killed.
            case State of #state{timer = Timer} ->
                clear_timeout(Timer)
            end;
        _Message ->
            listen(State, Propagate)
    end.

%% @doc retart the Timer
restart_timer(Timer) ->
    clear_timeout(Timer),
    Self = self(),
    Delay = get_delay(),
    set_timeout(fun()->
        Self ! continue
    end, [], Delay).

%% @doc Get a random delay
get_delay() ->
    Min = lynkia_config:get(mapreduce_observer_min_timeout),
    Max = lynkia_config:get(mapreduce_observer_max_timeout),
    Min + erlang:trunc(rand:uniform() * ((Max - Min) + 1)).

%% @doc Spawn a new process with a timer, after the Delay (timeout), Fun is run
set_timeout(Fun, Args, Delay) ->
    erlang:spawn(fun() ->
        timer:sleep(Delay),
        erlang:apply(Fun, Args)
    end).

%% @doc kill the Timer process
clear_timeout(Timer) ->
    case erlang:is_process_alive(Timer) of
        true ->
            erlang:exit(Timer, kill);
        false ->
            {noreply}
    end.