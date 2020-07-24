%%%-------------------------------------------------------------------
%% @doc
%% @author Julien Banken and Nicolas Xanthos
%% @end
%%%-------------------------------------------------------------------
-module(lynkia_mapreduce_map).
-include("lynkia.hrl").

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-export([
    start/2
]).

%% @doc
receive_all(State, Options) ->
    receive
        {add, Pairs} ->
            case State of
                #{jobs := 1, accumulator := Acc} ->
                    Result = add_pairs(Acc, Pairs),
                    {ok, Result};
                #{jobs := N, accumulator := Acc} ->
                    Result = add_pairs(Acc, Pairs),
                    receive_all(State#{
                        jobs := N - 1,
                        accumulator := Result
                    }, Options)
            end
    end.

%% @doc
start(Adapters, Options) ->
    N = map(Adapters, Options),
    receive_all(#{
        jobs => N,
        accumulator => []
    }, Options).

%% @doc
map(Adapters, Options) ->
    Self = self(),
    lists:foldl(fun(Adapter, N) ->
        case Adapter of
            {Module, Entries} ->
                Module:get_pairs(Entries, Options, fun(Pairs) ->
                    Self ! {add, Pairs}
                end),
                N + 1;
            _ -> N
        end
    end, 0, Adapters).

%% @doc
add_pairs(Acc, Pairs) when erlang:is_list(Pairs) ->
    Acc ++ lists:filter(fun(Pair) ->
        case Pair of
            {_, _} -> true;
            _ -> false
        end
    end, Pairs);
add_pairs(Acc, Pairs) ->
    add_pairs(Acc, [Pairs]).

% ---------------------------------------------
% EUnit tests:
% ---------------------------------------------

-ifdef(TEST).

%% @doc
map_lasp_adapter_test() ->

    lasp_sup:start_link(),

    Options = #options{
        max_round = 10,
        max_batch_size = 2,
        timeout = 3000
    },
    
    Var = {<<"var1">>, state_gset},
    lasp:bind(Var, {state_gset, [5, 3]}),
    lasp:read(Var, {cardinality, 2}),

    {ok, Pairs} = start([
        {lynkia_mapreduce_adapter_lasp, [
            {Var, fun(Value) ->
                [{key, Value}]
            end}
        ]}
    ], Options),

    ?assertEqual(
        lists:sort(Pairs),
        lists:sort([
            {key, 3},
            {key, 5}
        ])
    ),
    ok.

%% @doc
map_cvs_adapter_test() ->

    Options = #options{
        max_round = 10,
        max_batch_size = 2,
        timeout = 3000
    },

    {ok, Pairs} = start([
        {lynkia_mapreduce_adapter_csv, [
            {"dataset/test.csv", fun(Tuple) ->
                case Tuple of #{
                    temperature := Temperature,
                    country := Country
                } -> [{Country, Temperature}];
                _ -> [] end
            end}
        ]}
    ], Options),

    ?assertEqual(
        lists:sort(Pairs),
        lists:sort([
            {"Belgium", "15"},
            {"France", "14"},
            {"Spain", "18"},
            {"Greece", "20"}
        ])
    ),
    ok.

%% @doc
map_multiple_adapters_test() ->

    Options = #options{
        max_round = 10,
        max_batch_size = 2,
        timeout = 3000
    },

    Var = {<<"var2">>, state_gset},
    lasp:bind(Var, {state_gset, [{"Germany", "12"}]}),
    lasp:read(Var, {cardinality, 1}),

    {ok, Pairs} = start([
        {lynkia_mapreduce_adapter_lasp, [
            {Var, fun(Value) -> [Value] end}
        ]},
        {lynkia_mapreduce_adapter_csv, [
            {"dataset/test.csv", fun(Tuple) ->
                case Tuple of #{
                    temperature := Temperature,
                    country := Country
                } -> [{Country, Temperature}];
                _ -> [] end
            end}
        ]}
    ], Options),

    ?assertEqual(
        lists:sort(Pairs),
        lists:sort([
            {"Germany", "12"},
            {"Belgium", "15"},
            {"France", "14"},
            {"Spain", "18"},
            {"Greece", "20"}
        ])
    ),
    ok.

-endif.

% To launch the tests:
% rebar3 eunit --module=lynkia_mapreduce_map