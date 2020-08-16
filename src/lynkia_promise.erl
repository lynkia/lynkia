%%%-----------------------------------------------------------------------------
%%% @doc This module will be used to start asynchronous functions and get their results.
%%%
%%% @author Julien Banken and Nicolas Xanthos
%%% @end
%%%-----------------------------------------------------------------------------

-module(lynkia_promise).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

% API:
-export([
    all/1,
    all/2,
    all/3
]).

%% @doc
barrier(Tasks, Timeout) ->
    Parent = self(),
    lists:foreach(fun({ID, {Fun, Args}}) ->
        erlang:spawn(fun() ->
            Child = self(),
            Pid = erlang:spawn(fun() ->
                Result = erlang:apply(Fun, Args),
                Child ! {ok, {ID, Result}}
            end),
            receive {ok, Tuple} ->
                Parent ! {ok, Tuple}
            after Timeout ->
                erlang:exit(Pid, kill),
                Parent ! timeout
            end
        end)
    end, orddict:to_list(Tasks)),
    N = orddict:size(Tasks),
    barrier_loop(N, Tasks, orddict:new()).

%% @doc
barrier_loop(N, Tasks, Results) when N =< 0 ->
    {Tasks, Results};
barrier_loop(N, Tasks, Results) ->
    receive
        {ok, {ID, Result}} ->
            barrier_loop(
                N - 1,
                orddict:erase(ID, Tasks),
                orddict:store(ID, Result, Results)
            );
        timeout ->
            barrier_loop(
                N - 1,
                Tasks,
                Results
            )
    end.

%% @doc
all(Entries) ->
    all(Entries, #{
        max_attempts => 1,
        timeout => infinity
    }).

%% @doc
all(Entries, Options) ->
    all(Entries, fun(Tasks) -> Tasks end, Options).

%% @doc
all(Entries, Next, Options) ->
    case erlang:length(Entries) of
        N when N == 0 ->
            {ok, []};
        N when N > 0 ->
            Tasks = lists:zip(lists:seq(1, N), Entries),
            Results = orddict:new(),
            case Options of #{
                max_attempts := K,
                timeout := Timeout
            } -> retry_loop(K, Tasks, Results, Next, Timeout) end
    end.

%% @doc
retry_loop(N, Tasks, Results, _, _) when N =< 0 ->
    case orddict:is_empty(Tasks) of
        true -> {ok, Results};
        false -> max_attempts_reached
    end;
retry_loop(N, Tasks, Results, Next, Timeout) ->
    {UnfinishedTasks, AdditionalResults} = barrier(Tasks, Timeout),
    MergedResults = orddict:merge(
        fun(_, _, Value) ->
            Value
        end,
        Results,
        AdditionalResults
    ),
    case orddict:is_empty(UnfinishedTasks) of
        true ->
            {ok, MergedResults};
        false ->
            retry_loop(
                N - 1,
                erlang:apply(Next, [UnfinishedTasks]),
                MergedResults,
                Next,
                Timeout
            )
    end.

% ---------------------------------------------
% EUnit tests:
% ---------------------------------------------

-ifdef(TEST).

success_test() ->

    Options = #{
        max_attempts => 3,
        timeout => 500
    },

    case all([
        {fun() ->
            timer:sleep(200),
            40
        end, []},
        {fun() ->
            timer:sleep(150),
            42
        end, []}
    ], Options) of
        {ok, Results} ->
            ?assertEqual(Results, orddict:from_list([
                {1, 40},
                {2, 42}
            ]));
        max_attempts_reached ->
            ?assertEqual(true, false) % fail
    end.

timeout_test() ->

    Options = #{
        max_attempts => 3,
        timeout => 500
    },

    case all([
        {fun() ->
            timer:sleep(200),
            40
        end, []},
        {fun() ->
            timer:sleep(10000), % timeout
            42
        end, []}
    ], Options) of
        {ok, Results} ->
            ?assertEqual(true, false); % fail
        max_attempts_reached ->
            ?assertEqual(true, true) % success
    end.

-endif.

% To launch the tests:
% rebar3 eunit --module=lynkia_promise
