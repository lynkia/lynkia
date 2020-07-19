-module(test).
-include("lynkia.hrl").
-compile(export_all).

% test:map_reduce_test_2().

%%%-------------------------------------------------------------------
%%% Tests: lynkia_spawn
%%%-------------------------------------------------------------------

% @pre -
% @post -
spawn_test_async(N, MaxDelay) when MaxDelay > 0 ->
    lynkia_utils:repeat(N, fun(K) ->
        lynkia:spawn(fun() ->
            % timer:sleep(rand:uniform(MaxDelay)),
            timer:sleep(MaxDelay),
            K
        end, [], fun(Result) ->
            ?PRINT("Result ~p~n", [Result])
        end)
    end).

% @pre -
% @post -
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

% @pre -
% @post -
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

% @pre -
% @post -
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

% @pre -
% @post -
spawn_test_async_error() ->
    lynkia:spawn(fun() ->
        1 / 0 % Error
    end, [], fun(Result) ->
        ?PRINT("Result ~p~n", [Result])
    end).

% @pre -
% @post -
spawn_test_async_timeout() ->
    lynkia:spawn(fun() ->
        timer:sleep(5000)
    end, [], fun(Result) ->
        ?PRINT("Result ~p~n", [Result])
    end).

% @pre -
% @post -
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

% @pre -
% @post -
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

% @pre -
% @post -
map_reduce_test_2() ->

    Adapters = [
        {lynkia_mapreduce_adapter_file, [
            {"dataset/lorem-300k.txt", fun(Lines) ->
                lists:flatmap(fun(Line) ->
                    Separator = " ",
                    Words = string:tokens(Line, Separator),
                    lists:map(fun(Word) -> {Word, 1} end, Words)
                end, Lines)
            end}
        ]}
    ],

    Reduce = fun(Key, Values) ->
        % timer:sleep(20),
        [{Key, lists:sum(Values)}]
    end,

    Options = #options{
        max_round = 100,
        max_batch_size = 100,
        timeout = 3000
    },

    lynkia:mapreduce(Adapters, Reduce, Options, fun(Result) ->
        case Result of
            {ok, Pairs} ->
                Count = fun({_, N}, Total) -> N + Total end,
                ?PRINT("Pairs=~p~n", [Pairs]),
                ?PRINT("Words=~p~n", [lists:foldl(Count, 0, Pairs)]),
                ?PRINT("Length=~p~n", [erlang:length(Pairs)]);
            {error, Reason} ->
                ?PRINT("Error, Reason=~p~n", [Reason])
        end
    end).

% @pre -
% @post -
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
        max_batch_size = 2,
        timeout = 3000
    },

    lynkia:mapreduce(Adapters, Reduce, Options, fun(Result) ->
        io:format("Result=~p~n", [Result])
    end).
