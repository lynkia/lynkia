%%%-------------------------------------------------------------------
%% @doc This module has the responsibility to create batches and dispatch them.
%% @author Julien Banken and Nicolas Xanthos
%% @end
%%%-------------------------------------------------------------------
-module(lynkia_mapreduce_dispatcher).
-include("lynkia.hrl").

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-export([
    start/2,
    start/3
]).

%% @doc Start the dispatching of the pairs
start(Pairs, Reduce) ->
    start(Pairs, Reduce, #options{
        max_round = lynkia_config:get(mapreduce_max_round),
        max_batch_size = lynkia_config:get(mapreduce_max_batch_size),
        timeout = lynkia_config:get(mapreduce_round_timeout)
    }).

%% @doc Start the dispatching of the pairs
start(Pairs, Reduce, Options) ->
    N = dispatch(Pairs, Reduce, Options),
    io:format("Number of batches = ~p~n", [N]),
    io:format("Self=~p~n", [self()]),
    receive_all(#{
        jobs => N,
        accumulator => []
    }, Reduce, Options).

%% @doc The function will collect all pairs produced
receive_all(State, Reduce, Options) ->
    receive
        {add, Pairs} ->
            case State of
                #{jobs := N, accumulator := Acc} when N =< 1 ->
                    Result = add_pairs(Acc, Pairs),
                    {ok, Result};
                #{jobs := N, accumulator := Acc} ->
                    Result = add_pairs(Acc, Pairs),
                    receive_all(State#{
                        jobs := N - 1,
                        accumulator := Result
                    }, Reduce, Options)
            end;
        {split, Batch} when erlang:length(Batch) > 1 ->
            case State of
                #{jobs := N} ->
                    M = split_batch(Batch, Reduce),
                    receive_all(State#{
                        jobs := N - 1 + M
                    }, Reduce, Options)
            end;
        {split, _Batch} ->
            {error, "Could not divide a batch of length 1"};
        {error, Reason} ->
            {error, Reason}
    after 5000 ->
        case State of #{jobs := N} ->
            io:format("Remainging jobs=~p~n", [N])
        end,
        lynkia_spawn:debug(),
        receive_all(State, Reduce, Options)
    end.

%% @doc Add the pair to the accumulator.
%% The function will filter the pairs that do not respect the format {Key, Value}.
add_pairs(Acc, Pairs) when erlang:is_list(Pairs) ->
    Acc ++ lists:filter(fun(Pair) ->
        case Pair of
            {_, _} -> true;
            _ -> false
        end
    end, Pairs);
add_pairs(Acc, Pairs) ->
    add_pairs(Acc, [Pairs]).

%% @doc First pass of the shuffle
%% The function will produce batches of size n
%% The batch produced will be pure (no different keys within the same batch) 
first_pass(Pairs, Reduce, Options) ->
    Limit = Options#options.max_batch_size - 1,
    lists:foldl(fun(Pair, {N, Orddict}) ->
        {Key, _} = Pair,
        case orddict:find(Key, Orddict) of
            {ok, Group} when erlang:length(Group) >= Limit ->
                Batch = [Pair|Group],
                start_reduction(Batch, Reduce),
                {N + 1, orddict:erase(Key, Orddict)};
            _ ->
                {N, orddict:append(Key, Pair, Orddict)}
        end
    end, {0, orddict:new()}, Pairs).

%% @doc This function will be used to fill a batch
%% L1 - Remaining pairs
%% L2 - Rejected pairs
%% Batch - Batch
%% Options - Options
form_batch(L1, L2, Batch, Options) ->
    case L1 of
        [] -> {Batch, L2};
        [H2|T2] ->
            {_, Pairs} = H2,
            case {
                erlang:length(Batch) + erlang:length(Pairs),
                Options#options.max_batch_size
            } of
                {N, M} when N > M ->
                    form_batch(T2, L2 ++ [H2], Batch, Options);
                {N, M} when N < M ->
                    form_batch(T2, L2, Batch ++ Pairs, Options);
                {_, _} ->
                    {Batch ++ Pairs, L2 ++ T2}
            end
    end.

%% @doc The function will form a batch of size N
%% L - Remaining pairs
%% Reduce - Reduce function
%% Options - Options
form_batches(L1, N, Reduce, Options) ->
    case form_batch(L1, [], [], Options) of
        {Batch, L2} ->
            start_reduction(Batch, Reduce),
            M = N + 1,
            case L2 of [_|_] ->
                form_batches(L2, M, Reduce, Options);
            _ -> M end
    end.

%% @doc Second pass of the algorithm
%% The function will produce batches from the remaining pairs
%% The batch produced will be impure (there might be different keys within the same batch)
second_pass(Groups, Reduce, Options) ->
    L = lists:sort(fun({_, P1}, {_, P2}) ->
        erlang:length(P1) > erlang:length(P2)
    end, Groups),
    form_batches(L, 0, Reduce, Options).

%% @doc Group pairs per key
%% The function will produce that will associate to each key, the list of pairs having this key.
group_pairs_per_key(Pairs) ->
    Groups = lists:foldl(fun(Pair, Orddict) ->
        case Pair of {Key, Value} ->
            orddict:append(Key, Value, Orddict)
        end
    end, orddict:new(), Pairs),
    orddict:to_list(Groups).

%% @doc Return a function that perform the reduction
reduce(Reduce) ->
    fun(Batch) ->
        Groups = group_pairs_per_key(Batch),
        lists:flatmap(fun({Key, Pairs}) ->
            erlang:apply(Reduce, [Key, Pairs])
        end, Groups)
    end.

%% @doc Schedule a task to perform the reduction
start_reduction(Batch, Reduce) ->
    Self = self(),
    lynkia:spawn(reduce(Reduce), [Batch], fun(Result) ->
        case Result of
            {ok, Pairs} ->
                % logger:info("[MAPREDUCE]: message=~p;pairs=~p~n", ["SR ok", Pairs]),
                Self ! {add, Pairs};
            {error, Reason} ->
                % logger:info("[MAPREDUCE]: message=~p;error=~p~n", ["SR error", Reason]),
                Self ! {error, Reason};
            timeout ->
                % logger:info("[MAPREDUCE]: message=~p~n", ["SR timeout"]),
                Self ! {split, Batch};
            killed ->
                % logger:info("[MAPREDUCE]: message=~p~n", ["SR killed"]),
                Self ! {split, Batch}
        end
    end).

%% @doc Form batch 
dispatch(Pairs, Reduce, Options) ->
    {N, Groups} = first_pass(Pairs, Reduce, Options),
    M = second_pass(Groups, Reduce, Options),
    N + M.

%% @doc Split the given pairs in two batches
split_batch(Pairs, Reduce) ->
    N = erlang:length(Pairs),
    Options = #options{
        max_batch_size = erlang:ceil(N / 2)
    },
    dispatch(Pairs, Reduce, Options).

% ---------------------------------------------
% EUnit tests:
% ---------------------------------------------

-ifdef(TEST).

% First pass: Forming full batch

first_pass_1_test() ->
    F = fun()-> ok end,
    Options = #options{
        max_batch_size = 2
    },
    Pairs = [{key1, value1}, {key2, value3}, {key1, value2}],
    {N, Orddict} = first_pass(Pairs, F, Options),
    ?assertEqual(N, 1),
    ?assertEqual(Orddict, orddict:from_list([
        {key2, [{key2, value3}]}
    ])),
    ok.

first_pass_2_test() ->
    F = fun()-> ok end,
    Options = #options{
        max_batch_size = 2
    },
    Pairs = [
        {key1, value1}, {key1, value3}, {key1, value4}, {key1, value5}, {key1, value6},
        {key2, value7}, {key2, value8}, {key2, value9}, {key1, value2}
    ],
    {N, Orddict} = first_pass(Pairs, F, Options),
    ?assertEqual(N, 4),
    ?assertEqual(Orddict, orddict:from_list([
        {key2, [{key2, value9}]}
    ])),
    ok.

% Second pass: Merging remaining pairs

second_pass_1_test() ->
    F = fun()-> ok end,
    Options = #options{
        max_batch_size = 2
    },
    Groups = [
        {key2, [{key2, value3}]},
        {key3, [{key3, value3}]}
    ],
    ?assertEqual(second_pass(Groups, F, Options), 1),
    ok.

second_pass_2_test() ->
    F = fun() -> ok end,
    Options = #options{
        max_batch_size = 5
    },
    Groups = [
        {key2, [{key2, value3}, {key2, value4}, {key2, value5}]},
        {key3, [{key3, value3}]},
        {key1, [{key1, value3}, {key1, value4}]}
    ],
    ?assertEqual(second_pass(Groups, F, Options), 2),
    ok.

second_pass_3_test() ->
    F = fun() -> ok end,
    Options = #options{
        max_batch_size = 5
    },
    Groups = [
        {key2, [{key2, value3}, {key2, value4}, {key2, value5}, {key2, value6}]},
        {key3, [{key3, value3}]},
        {key1, [{key1, value3}, {key1, value4}]}
    ],
    ?assertEqual(second_pass(Groups, F, Options), 2),
    ok.

dispatch_test() ->
    F = fun() -> ok end,
    Options = #options{
        max_batch_size = 2
    },
    Pairs = [
        {key1, value1}, {key1, value3}, {key1, value4}, {key1, value5}, {key1, value6},
        {key2, value7}, {key2, value8}, {key2, value9}, {key1, value2}
    ],
    ?assertEqual(dispatch(Pairs, F, Options), 5),
    ok.

split_batch_1_test() ->
    F = fun() -> ok end,
    Pairs = [{key1, value1}, {key1, value3}, {key1, value4}, {key1, value5}, {key1, value6}],
    ?assertEqual(split_batch(Pairs, F), 2),
    ok.

split_batch_2_test() ->
    F = fun() -> ok end,
    Pairs = [{key4, value1}, {key2, value3}, {key2, value4}, {key2, value6}, {key4, value5}],
    ?assertEqual(split_batch(Pairs, F), 2),
    ok.

add_pairs_test() ->
    ?assertEqual(add_pairs([], 2), []),
    ?assertEqual(add_pairs([], {2, 4}), [{2, 4}]),
    ?assertEqual(add_pairs([{2, 4}], {2, 4}), [{2, 4}, {2, 4}]),
    ?assertEqual(add_pairs([{2, 4}], [{2, 4}]), [{2, 4}, {2, 4}]),
    ?assertEqual(add_pairs([], {}), []),
    ?assertEqual(add_pairs([], [{}]), []),
    ?assertEqual(add_pairs([{2, 4}, {6, 8}], [{2, 4}, {10, 10}]), [{2, 4}, {6, 8}, {2, 4}, {10, 10}]),
    ok.

-endif.

% To launch the tests:
% rebar3 eunit --module=lynkia_mapreduce_dispatcher