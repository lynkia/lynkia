%%%-------------------------------------------------------------------
%% @doc This module contains the logic of the leader.
%% @author Julien Banken and Nicolas Xanthos
%% @end
%%%-------------------------------------------------------------------
-module(lynkia_mapreduce_leader).
-include("lynkia.hrl").

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

% API:

-export([
    start/2
]).

-record(state, {
    deamon :: identifier(),
    worker :: identifier(),
    data :: list()
}).

%% @doc Start a leader
%% Round - Round number
%% Pairs - Input pairs
%% Reduce - Reduce function
%% Options - Options
%% Propagate - Function to propagate the messages
start([_Round, _Pairs, _Reduce, _Options] = Data, Propagate) ->
    % Myself = lynkia_utils:myself(),
    % logger:info("[MAPREDUCE]: node=~p;type=~p;round=~p", [Myself, "leader", Round]),
    State = init(Data, Propagate),
    listen(State, Propagate).

%% @doc Initialize the state of the leader
init([Round, Pairs, Reduce, Options] = Data, Propagate) ->
    case Round == 0 of
        true ->
            erlang:apply(Propagate, [
                {notify, [
                    Round,
                    Pairs,
                    Reduce,
                    Options
                ]}
            ]);
        false -> ok
    end,
    Deamon = send_heartbeat_periodically(Propagate),
    Worker = reduce(Round + 1, Pairs, Reduce, Options, Propagate),
    #state{
        deamon = Deamon,
        worker = Worker,
        data = Data
    }.

%% @doc Loop function that receives the incoming messages.
%% The function will process the messages sent by the other nodes.
%% When the node receives a more advanced checkpoint from another node, the node will become an observer.
listen(State, Propagate) ->
    receive
        {notify, NewRound, NewPairs} ->
            % When the other leader is more advanced, the node becomes an observer
            case State of #state{
                deamon = Deamon,
                worker = Worker,
                data = [Round, _Pairs, Reduce, Options]
            } when NewRound > Round ->
                kill(Deamon),
                kill(Worker),
                lynkia_mapreduce_observer:start([
                    NewRound,
                    NewPairs,
                    Reduce,
                    Options
                ], Propagate);
            _ ->
                listen(State, Propagate)
            end;
        stop ->
            case State of #state{deamon = Deamon, worker = Worker} ->
                % Myself = lynkia_utils:myself(),
                % logger:info("[STOP-MAPREDUCE]: node=~p;type=~p;message=~p", [Myself, "leader", "stop"]),
                kill(Deamon),
                kill(Worker)
            end;
        _Message ->
            listen(State, Propagate)
    end.

% Reduce phase:

%% @doc Spawn a new process that will be responsible of the reduction
reduce(Round, InputPairs, Reduce, Options, Propagate) ->
    erlang:spawn(fun() ->
        new_round(Round, InputPairs, Reduce, Options, Propagate)
    end).

%% @doc Start a new Round
new_round(Round, InputPairs, Reduce, Options, Propagate) ->
    case Round =< Options#options.max_round of
        false ->
            erlang:apply(Propagate, [
                {return, [{error, "Max round reached"}]}
            ]);
        true ->
            start_reduction(
                Round,
                InputPairs,
                Reduce,
                Options,
                Propagate
            )
    end.

%% @doc Return true if the input pairs of the round is equal to its output pair
is_irreductible(InputPairs, OutputPairs) ->
    lists:sort(InputPairs) == lists:sort(OutputPairs).

%% @doc Start the reduction
start_reduction(Round, InputPairs, Reduce, Options, Propagate) ->
    case dispatch(InputPairs, Reduce, Options) of
        {error, Reason} ->
            Myself = lynkia_utils:myself(),
            logger:info("[ERROR-MAPREDUCE]: node=~p;type=~p;error=~p", [Myself, "leader", Reason]),
            erlang:apply(Propagate, [
                {return, [{error, Reason}]}
            ]);
        {ok, OutputPairs} ->
            % Myself = lynkia_utils:myself(),
            % logger:info("[MAPREDUCE]: node=~p;type=~p;round=~p", [Myself, "leader", Round]),
            case is_irreductible(InputPairs, OutputPairs) of
                true ->
                    erlang:apply(Propagate, [
                        {return, [{ok, OutputPairs}]}
                    ]);
                false ->
                    erlang:apply(Propagate, [
                        {notify, [
                            Round,
                            OutputPairs,
                            Reduce,
                            Options
                        ]}
                    ]),
                    new_round(
                        Round + 1,
                        OutputPairs,
                        Reduce,
                        Options,
                        Propagate
                    )
            end
    end.

%% @doc Dispatch the tasks to other nodes
dispatch(InputPairs, Reduce, Options) ->
    %% TODO: Add method fork
    Self = self(),
    erlang:spawn(fun() ->
        Self ! lynkia_mapreduce_dispatcher:start(
            InputPairs,
            Reduce,
            Options
        )
    end),
    receive Result -> Result end.

%% @doc Loop function with a Delay between each repeat
%% Fun - Function to execute
%% Delay - Delay between each execution
repeat(Fun, Delay) ->
    receive
    after Delay ->
        erlang:apply(Fun, []),
        repeat(Fun, Delay)
    end.

%% @doc Spawn a new process that will send heartbeat messages
send_heartbeat_periodically(Propagate) ->
    Delay = lynkia_config:get(mapreduce_leader_heartbeat_delay),
    erlang:spawn(fun() ->
        repeat(fun() ->
            erlang:apply(Propagate, [heartbeat])
        end, Delay)
    end).

%% @doc Kill the given process.
kill(Pid) ->
    case erlang:is_process_alive(Pid) of
        true ->
            erlang:exit(Pid, kill);
        false ->
            {noreply}
    end.

% ---------------------------------------------
% EUnit tests:
% ---------------------------------------------

-ifdef(TEST).

master_1_test() ->

    lynkia_sup:start_link(),

    InputPairs = [
        {a, 4},
        {a, 6},
        {b, 3},
        {b, 7}
    ],
    
    Reduce = fun(Key, Values) ->
        case Key of
            a -> [{a, lists:foldl(fun(E, Acc) -> E + Acc end, 0, Values)}];
            b -> lists:map(fun(E) -> {a, 2 * E} end, Values);
        _ -> [] end
    end,

    Options = #options{
        max_round = 10,
        max_batch_size = 2,
        timeout = 3000
    },

    Self = self(),
    lynkia_mapreduce_leader:start([0, InputPairs, Reduce, Options], fun(Message) ->
        case Message of
            {return, [Result]} ->
                Self ! Result;
            _ ->
                ?debugVal(Message)
        end
    end),

    receive {ok, OutputPairs} ->
        ?debugVal(OutputPairs),
        ?assertEqual(
            lists:sort(OutputPairs),
            lists:sort([{a, 30}])
        )
    end.

master_2_test() ->

    InputPairs = [
        {"These", 1},
        {"are", 1},
        {"my", 1},
        {"cats", 1},
        {"The", 1},
        {"cats", 1},
        {"are", 1},
        {"over", 1},
        {"there", 1},
        {"I", 1},
        {"love", 1},
        {"cats", 1}
    ],

    Reduce = fun(Key, Values) ->
        [{Key, lists:sum(Values)}]
    end,

    Options = #options{
        max_round = 10,
        max_batch_size = 2,
        timeout = 3000
    },

    Self = self(),
    start([0, InputPairs, Reduce, Options], fun(Message) ->
        case Message of
            {return, [Result]} ->
                Self ! Result;
            _ ->
                ?debugVal(Message)
        end
    end),

    receive {ok, OutputPairs} ->
        ?assertEqual(
            lists:sort(OutputPairs),
            lists:sort([
                {"These", 1},
                {"are", 2},
                {"my", 1},
                {"cats", 3},
                {"The", 1},
                {"over", 1},
                {"there", 1},
                {"I", 1},
                {"love", 1}
            ])
        )
    end,
    ok.

-endif.

% To launch the tests:
% rebar3 eunit --module=lynkia_mapreduce_leader