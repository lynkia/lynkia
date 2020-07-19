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

% @pre -
% @post -
start([_Round, _Pairs, _Reduce, _Options] = Data, Propagate) ->
    erlang:spawn(fun() ->
        State = init(Data, Propagate),
        listen(State, Propagate)
    end).

% @pre -
% @post -
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

% @pre -
% @post -
listen(State, Propagate) ->
    receive
        {notify, NewRound, NewPairs} ->
            % When the other leader is more advanced, the node becomes an observer
            case State of #state{
                deamon = Deamon,
                worker = Worker,
                data = [Round, _Pairs, Reduce, Options]
            } when NewRound > Round ->
                io:format("[MAPREDUCE]: message=~p;observer=~p~n", ["notify", lynkia_utils:myself()]),
                kill(Deamon),
                kill(Worker),
                lynkia_mapreduce_observer:start([
                    NewRound,
                    NewPairs,
                    Reduce,
                    Options
                ], Propagate);
            _ ->
                io:format("[MAPREDUCE]: message=~p;leader=~p~n", ["notify", lynkia_utils:myself()]),
                listen(State, Propagate)
            end;
        stop ->
            case State of #state{deamon = Deamon, worker = Worker} ->
                kill(Deamon),
                kill(Worker),
                io:format("[MAPREDUCE]: message=~p;leader=~p~n", ["stop", lynkia_utils:myself()])
            end;
        Message ->
            io:format("[MAPREDUCE]: message=~p;leader=~p~n", [Message, lynkia_utils:myself()]),
            listen(State, Propagate)
    end.

% Reduce phase:

% @pre -
% @post -
reduce(Round, InputPairs, Reduce, Options, Propagate) ->
    erlang:spawn(fun() ->
        new_round(Round, InputPairs, Reduce, Options, Propagate)
    end).

% @pre -
% @post -
new_round(Round, InputPairs, Reduce, Options, Propagate) ->
    case Round =< Options#options.max_round of
        false ->
            erlang:apply(Propagate, [
                {return, [{error, "Max round reached"}]}
            ]);
        true ->
            io:format("[MAPREDUCE]: round=~p;master=~p~n", [Round, lynkia_utils:myself()]),
            start_reduction(
                Round,
                InputPairs,
                Reduce,
                Options,
                Propagate
            )
    end.

% @pre -
% @post -
is_irreductible(InputPairs, OutputPairs) ->
    lists:sort(InputPairs) == lists:sort(OutputPairs).

% @pre -
% @post -
start_reduction(Round, InputPairs, Reduce, Options, Propagate) ->
    case dispatch(InputPairs, Reduce, Options) of
        {error, Reason} ->
            erlang:apply(Propagate, [
                {return, [{error, Reason}]}
            ]);
        {ok, OutputPairs} ->
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

% @pre -
% @post -
dispatch(InputPairs, Reduce, Options) ->
    % TODO: Add method fork
    lynkia_mapreduce_dispatcher:start(InputPairs, Reduce, Options).

% @pre -
% @post -
repeat(Fun, Delay) ->
    receive
    after Delay ->
        erlang:apply(Fun, []),
        repeat(Fun, Delay)
    end.

% @pre -
% @post -
send_heartbeat_periodically(Propagate) ->
    erlang:spawn(fun() ->
        repeat(fun() ->
            erlang:apply(Propagate, [heartbeat])
        end, 1000)
    end).

% @pre -
% @post -
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

% @pre -
% @post -
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

% @pre -
% @post -
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