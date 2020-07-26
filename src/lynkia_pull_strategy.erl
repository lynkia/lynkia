%%%-------------------------------------------------------------------
%% @doc
%% @author Julien Banken and Nicolas Xanthos
%% @end
%%%-------------------------------------------------------------------
-module(lynkia_pull_strategy).
-behaviour(gen_server).

-include("lynkia.hrl").
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-export([
    init/1,
    start_link/0,
    handle_cast/2,
    handle_call/3,
    handle_info/2,
    terminate/2
]).

-export([
    on/1,
    debug/0
]).

%% @doc
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc
init([]) ->
    {ok, #{
        number_of_tasks => 0,
        daemon => start_daemon()
    }}.

%% @doc
handle_cast({on, #lynkia_spawn_add_event{queue = tasks}}, State) ->
    case State of #{number_of_tasks := N, daemon := Pid} ->
        case N > 100 of
            true -> stop_daemon(Pid);
            false -> ok
        end,
        {noreply, State#{
            number_of_tasks := N + 1
        }}
    end;

%% @doc
handle_cast({on, #lynkia_spawn_remove_event{queue = tasks}}, State) ->
    case State of #{number_of_tasks := N, daemon := Pid} ->
        case N < 100 of
            true ->
                {noreply, State#{
                    daemon := start_daemon(Pid),
                    number_of_tasks := N - 1
                }};
            false ->
                {noreply, State#{
                    number_of_tasks := N - 1
                }}
        end
    end;


%% @doc
handle_cast({steal, N, Node}, State) ->
    % io:format("The node ~p is asking ~p tasks (number of tasks = ~p) ~n", [Node, N, maps:get(number_of_tasks, State)]),
    lynkia_spawn:forward(N, Node),
    {noreply, State};

%% @doc
handle_cast(daemon, State) ->
    case State of #{number_of_tasks := N} when N < 100 ->
        Myself = lynkia_utils:myself(),
        Nodes = lynkia_utils:get_neighbors(),
        lists:foreach(fun(Node) ->
            send(Node, {steal, 100 - N, Myself})
        end, Nodes);
    _ -> ok end,
    {noreply, State};

%% @doc
handle_cast(debug, State) ->
    ?PRINT("State: ~p~n", [State]),
    {noreply, State};

%% @doc
handle_cast(_Message, State) ->
    {noreply, State}.

%% @doc
handle_call(_Request, _From, State) ->
    {noreply, State}.

%% @doc
handle_info(_Info, State) ->
    {noreply, State}.

%% @doc
terminate(_Reason, _State) ->
    ok.

% Helpers:

%% @doc
send(Node, Message) ->
    partisan_peer_service:cast_message(Node, ?MODULE, Message).

%% @doc
loop() ->
    timer:sleep(1000),
    gen_server:cast(?MODULE, daemon),
    loop().

%% @doc
start_daemon() ->
    erlang:spawn(fun loop/0).
start_daemon(Pid) ->
    case erlang:is_process_alive(Pid) of
        true -> Pid;
        false -> erlang:spawn(fun loop/0)
    end.

%% @doc
stop_daemon(Pid) ->
    case erlang:is_process_alive(Pid) of
        true ->
            erlang:exit(Pid, kill),
            Pid;
        false ->
            Pid
    end.

% API:

%% @doc
on(Event) ->
    gen_server:cast(?MODULE, {on, Event}).

%% @doc
debug() ->
    gen_server:cast(?MODULE, debug).

% ---------------------------------------------
% EUnit tests:
% ---------------------------------------------

-ifdef(TEST).

-endif.

% To launch the tests:
% rebar3 eunit --module=lynkia_pull_strategy