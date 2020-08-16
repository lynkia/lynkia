%%%-------------------------------------------------------------------
%% @doc This module contains some tests 
%% allowing to test the task model and the MapReduce
%%
%% @author Julien Banken and Nicolas Xanthos
%% @end
%%%-------------------------------------------------------------------

-module(test).
-include("lynkia.hrl").
-export([
    spawn_test_async/2,
    spawn_test_sync/2,
    spawn_test_async_burst/3,
    spawn_test_sync_burst/3,
    spawn_test_async_benchmark/2,
    spawn_test_async_error/0,
    spawn_test_async_timeout/0,
    spawn_test_debug/0,
    map_reduce_test_1/0,
    map_reduce_test_2/1,
    map_reduce_test_3/0,
    synthetic_test/0
]).

%%%-------------------------------------------------------------------
%%% Tests: lynkia_spawn
%%%-------------------------------------------------------------------

%% @doc
spawn_test_async(N, MaxDelay) when MaxDelay > 0 ->
    Start = lynkia_utils:now(),
    lynkia_utils:repeat(N, fun(K) ->
        lynkia:spawn(fun() ->
            % timer:sleep(rand:uniform(MaxDelay)),
            timer:sleep(MaxDelay),
            K
        end, [], fun(Result) ->
            Max = N - 1,
            case Result of
                {ok, Max} ->
                    End = lynkia_utils:now(),
                    io:format("Delay = ~p~n", [End - Start]);
                _ -> ok
            end
        end)
    end).

%% @doc
spawn_test_sync(N, MaxDelay) when MaxDelay > 0 ->
    lynkia_utils:repeat(N, fun(K) ->
        erlang:spawn(fun() ->
            Result = lynkia:spawn(fun() ->
                % timer:sleep(rand:uniform(MaxDelay)),
                timer:sleep(MaxDelay),
                K
            end, []),
            ?PRINT("Result ~p~n", [Result])
        end)
    end).

%% @doc
spawn_test_async_burst(N, M, MaxDelay) ->
    lynkia_utils:repeat(N, fun(I) ->
        timer:sleep(120), % Wait 120ms before the next burst
        lynkia_utils:repeat(M, fun(J) ->
            lynkia:spawn(fun() ->
                % timer:sleep(rand:uniform(MaxDelay)),
                timer:sleep(MaxDelay),
                I * M + J
            end, [], fun(Result) ->
                ?PRINT("Result ~p~n", [Result])
            end)
        end)
    end).

%% @doc
spawn_test_sync_burst(N, M, MaxDelay) ->
    lynkia_utils:repeat(N, fun(I) ->
        % timer:sleep(120), % Wait 120ms before the next burst
        lynkia_utils:repeat(M, fun(J) ->
            erlang:spawn(fun() ->
                Result = lynkia:spawn(fun() ->
                    % timer:sleep(rand:uniform(MaxDelay)),
                    timer:sleep(MaxDelay),
                    I * M + J
                end, []),
                ?PRINT("Result ~p~n", [Result])
            end)
        end)
    end).

%% @doc
spawn_test_async_benchmark(N, Delay) ->
    Start = lynkia_utils:now(),
    Tasks = lists:map(fun(K) ->
        {fun() ->
            lynkia:spawn(fun() ->
                timer:sleep(Delay),
                K
            end, [])
        end, []}
    end, lists:seq(1, N)),
    case lynkia_promise:all(Tasks) of {ok, _Result} ->
        End = lynkia_utils:now(),
        io:format("Delay = ~p~n", [End - Start])
    end.

%% @doc
spawn_test_async_error() ->
    Num = 1,
    Den = rand:uniform(1),
    lynkia:spawn(fun() ->
        Num / (Den - 1)% Error
    end, [], fun(Result) ->
        ?PRINT("Result ~p~n", [Result])
    end).

%% @doc
spawn_test_async_timeout() ->
    lynkia:spawn(fun() ->
        timer:sleep(5000)
    end, [], fun(Result) ->
        ?PRINT("Result ~p~n", [Result])
    end).

%% @doc
spawn_test_debug() ->
    lynkia_utils:repeat(10, fun(_) ->
        lynkia:spawn(fun() ->
            timer:sleep(3000)
        end, [], fun(Result) ->
            ?PRINT("Result ~p~n", [Result])
        end)
    end),
    timer:sleep(1000),
    lynkia_spawn:debug().

%%%-------------------------------------------------------------------
%%% Tests: lynkia_map_reduce
%%%-------------------------------------------------------------------

%% @doc
map_reduce_test_1() ->

    Adapters = [
        {lynkia_mapreduce_adapter_csv, [
            {"dataset/test.csv", fun(Tuple) ->
                case Tuple of #{
                    temperature := Temperature,
                    country := Country
                } -> [{Country, erlang:list_to_integer(Temperature)}];
                _ -> [] end
            end}
        ]}
    ],

    Reduce = fun(Key, Values) ->
        [{Key, lists:max(Values)}]
    end,

    lynkia:mapreduce(Adapters, Reduce, fun(Result) ->
        case Result of {ok, Pairs} ->
            ?PRINT("Pairs=~p~n", [Pairs])
        end
    end).

%% @doc
map_reduce_test_2(Path) ->
    Adapters = [
        {lynkia_mapreduce_adapter_file, [
            {Path, fun(Lines) ->
                lists:flatmap(fun(Line) ->
                    Separator = " ",
                    Words = string:tokens(Line, Separator),
                    lists:map(fun(Word) -> {Word, 1} end, Words)
                end, Lines)
            end}
        ]}
    ],

    Reduce = fun(Key, Values) ->
        timer:sleep(10),
        [{Key, lists:sum(Values)}]
    end,

    Options = #options{
        max_round = 100,
        max_batch_size = 50,
        timeout = 5000
    },

    lynkia:mapreduce(Adapters, Reduce, Options, fun(Result) ->
        case Result of
            {ok, Pairs} ->
                Count = fun({_, N}, Total) -> N + Total end,
                % ?PRINT("Pairs=~p~n", [Pairs]),
                ?PRINT("Words=~p~n", [lists:foldl(Count, 0, Pairs)]),
                ?PRINT("Length=~p~n", [erlang:length(Pairs)]);
            {error, Reason} ->
                ?PRINT("Error, Reason=~p~n", [Reason])
        end
    end).

%% @doc
map_reduce_test_3() ->

    Var = {<<"var">>, state_gset},
    lasp:bind(Var, {state_gset, [5, 3, 2, 6]}),
    lasp:read(Var, {cardinality, 4}),

    Adapters = [
        {lynkia_mapreduce_adapter_lasp, [
            {Var, fun(Value) ->
                case Value rem 2 == 0 of
                    true ->
                        [{even, Value}];
                    false ->
                        [{odd, Value}]
                end
            end}
        ]}
    ],

    Reduce = fun(Key, Values) ->
        case Key of
            even -> [{even, lists:foldl(fun(E, Acc) -> E + Acc end, 0, Values)}];
            odd -> lists:map(fun(E) -> {even, 2 * E} end, Values);
        _ -> [] end
    end,

    Options = #options{
        max_round = 10,
        max_batch_size = 100,
        timeout = 5000
    },

    lynkia:mapreduce(Adapters, Reduce, Options, fun(Result) ->
        io:format("Result=~p~n", [Result])
    end).

%% @doc
synthetic_test() ->

    Max = 100,
    Var = {<<"var">>, state_gset},
    lasp:bind(Var, {state_gset, lists:seq(0, Max)}),
    lasp:read(Var, {cardinality, Max}),

    Adapters = [
        {lynkia_mapreduce_adapter_lasp, [
            {Var, fun(Value) ->
                [{0, Value}]
            end}
        ]}
    ],

    Reduce = fun(Key, Values) ->
        timer:sleep(100),
        case Key < 10 of % Number of rounds = 10
            true ->
                lists:map(fun(Value) ->
                    {Key + 1, Value}
                end, Values);
            false ->
                lists:map(fun(Value) ->
                    {Key, Value}
                end, Values)
        end
    end,

    Options = #options{
        max_round = 100,
        max_batch_size = 2,
        timeout = 5000
    },

    lynkia:mapreduce(Adapters, Reduce, Options, fun(Result) ->
        io:format("Result=~p~n", [Result])
    end).