%%%-------------------------------------------------------------------
%% @doc
%% @author Julien Banken and Nicolas Xanthos
%% @end
%%%-------------------------------------------------------------------
-module(lynkia_spawn).
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
    schedule/2,
    schedule/3,
    forward/2,
    debug/0
]).

% =============================================
% Records:
% =============================================

-record(task, {
    id :: any(),
    function :: function(),
    arguments = [] :: list(),
    callback :: function(),
    hops = [] :: list()
}).

-record(header, {
    src :: any()
}).

-record(message, {
    header :: #header{},
    body :: any()
}).

%% @doc
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc
init([]) ->
    erlang:send_after(?LOG_INTERVAL, ?MODULE, write_log),
    {ok, #{
        tasks => orddict:new(),
        queue => queue:new(),
        running_tasks => orddict:new(),
        forwarded_tasks => orddict:new()
    }}.

%% @doc
send(Node, Message) ->
    partisan_peer_service:cast_message(Node, ?MODULE, #message{
        header = #header{
            src = lynkia_utils:myself()
        },
        body = Message
    }).

%% @doc
get_task(ID, State) ->
    Tasks = maps:get(tasks, State),
    orddict:find(ID, Tasks).

%% @doc
add_task(Task, State) ->
    ID = Task#task.id,
    maps:update_with(tasks, fun(Tasks) ->
        lynkia_spawn_monitor:on(#lynkia_spawn_add_event{
            id = ID,
            target = lynkia_utils:myself(),
            queue = tasks
        }),
        orddict:store(ID, Task, Tasks)
    end, State).

%% @doc
add_to_queue(Task, State) ->
    ID = Task#task.id,
    maps:update_with(queue, fun(Q) ->
        queue:in(ID, Q)
    end, State).

%% @doc
worker(Parent, Fun, Args) ->
    Opts = [
        link,
        {max_heap_size, #{
            size => 0,
            kill => true,
            error_logger => false
        }}
    ],
    erlang:spawn_opt(fun() ->
        try erlang:apply(Fun, Args) of
            Result ->
                Parent ! {ok, Result}
            catch
                error:Error ->
                    Parent ! {error, Error};
                throw:Error ->
                    Parent ! {error, Error};
                exit:Error ->
                    Parent ! {error, Error}
        end
    end, Opts).

%% @doc
execute_function(Task) ->
    case Task of #task{
        id = ID,
        function = Fun,
        arguments = Args
    } ->
        erlang:spawn(fun () ->
            process_flag(trap_exit, true),
            Pid = worker(self(), Fun, Args),
            Myself = lynkia_utils:myself(),
            receive
                {ok, Result} ->
                    Term = {return, ID, Myself, {ok, Result}},
                    gen_server:cast(?MODULE, Term);
                {error, Error} ->
                    Term = {return, ID, Myself, {error, Error}},
                    gen_server:cast(?MODULE, Term);
                {'EXIT', _Parent, _Reason} ->
                    Term = {return, ID, Myself, killed},
                    gen_server:cast(?MODULE, Term)
            after ?TIMEOUT ->
                erlang:exit(Pid, shutdown),
                Term = {return, ID, Myself, timeout},
                gen_server:cast(?MODULE, Term)
            end
        end)
    end.

%% @doc
add_to_running(Task, State) ->
    maps:update_with(running_tasks, fun(RunningTasks) ->
        ID = Task#task.id,
        Pid = execute_function(Task),
        lynkia_spawn_monitor:on(#lynkia_spawn_add_event{
            id = ID,
            target = lynkia_utils:myself(),
            queue = running
        }),
        orddict:store(ID, Pid, RunningTasks)
    end, State).

%% @doc
add_to_forwarded(Node, Task, State) ->
    ID = Task#task.id,
    maps:update_with(forwarded_tasks, fun(ForwardedTasks) ->
        ID = Task#task.id,
        send(Node, {schedule, Task#task{
            hops = [lynkia_utils:myself()|Task#task.hops]
        }}),
        lynkia_spawn_monitor:on(#lynkia_spawn_add_event{
            id = ID,
            target = Node,
            queue = forwarded
        }),
        orddict:store(ID, Node, ForwardedTasks)
    end, State).

%% @doc
run_task(N, Q, State) when N > 0 ->
    case queue:out(Q) of
        {empty, _} ->
            State;
        {{value, ID}, Queue} ->
            RunningTasks = maps:get(running_tasks, State),
            case orddict:is_key(ID, RunningTasks) of
                true ->
                    run_task(N, Queue, State);
                false ->
                    case get_task(ID, State) of
                        {ok, Task} ->
                            S1 = add_to_running(Task, State),
                            run_task(N - 1, Queue, S1)
                    end
            end
    end;
run_task(_N, _Q, State) -> State.

%% @doc
run_tasks(State) ->
    case State of
        #{queue := Q, running_tasks := RunningTasks} ->
            N = ?MAX_RUNNING - orddict:size(RunningTasks),
            run_task(N, Q, State)
    end.

%% @doc
is_forwarded(Task, State) ->
    case State of #{forwarded_tasks := ForwardedTasks} ->
        ID = Task#task.id,
        orddict:is_key(ID, ForwardedTasks)
    end.

%% @doc
forward_task(N, Node, Q, State) when N > 0 ->
    case queue:out_r(Q) of
        {empty, _} -> State;
        {{value, ID}, Queue} ->
            case get_task(ID, State) of {ok, Task} ->
                case is_forwarded(Task, State) of
                    true ->
                        forward_task(N, Node, Queue, State);
                    false ->
                        Hops = Task#task.hops,
                        case lists:member(Node, Hops) of
                            true ->
                                forward_task(N, Node, Queue, State);
                            false ->
                                S1 = add_to_forwarded(Node, Task, State),
                                forward_task(N - 1, Node, Queue, S1)
                        end
                end
            end
    end;
forward_task(_N, _Node, _Q, State) -> State.

%% @doc
forward_tasks(N, Node, State) ->
    case State of #{queue := Q} ->
        case queue:len(Q) > ?FORWARDING_THRESHOLD of
            true ->
                {_Q1, Q2} = queue:split(?FORWARDING_THRESHOLD, Q),
                forward_task(N, Node, Q2, State);
            false ->
                State
        end
    end.

%% @doc
remove_from_running(ID, From, Reason, State) ->
    case State of #{running_tasks := RunningTasks} ->
        case orddict:find(ID, RunningTasks) of
            {ok, Pid} ->
                kill(Pid),
                lynkia_spawn_monitor:on(#lynkia_spawn_remove_event{
                    id = ID,
                    from = From,
                    reason = Reason,
                    queue = running
                }),
                maps:update(
                    running_tasks,
                    orddict:erase(ID, RunningTasks),
                    State
                );
            error -> State
        end
    end.

%% @doc
remove_from_forwarded(ID, From, Reason, State) ->
    case State of #{forwarded_tasks := ForwardedTasks} ->
        case orddict:find(ID, ForwardedTasks) of
            {ok, Worker} ->
                case Worker == From of 
                    true -> ok;
                    false -> send(Worker, {kill, ID})
                end,
                lynkia_spawn_monitor:on(#lynkia_spawn_remove_event{
                    id = ID,
                    from = From,
                    reason = Reason,
                    queue = forwarded
                }),
                maps:update(
                    forwarded_tasks,
                    orddict:erase(ID, ForwardedTasks),
                    State
                );
            error -> State
        end
    end.

%% @doc
remove_from_queue(ID, State) ->
    case State of #{queue := Q} ->
        maps:update(
            queue,
            queue:filter(fun(X) ->
                not (X == ID)
            end, Q),
            State
        )
    end.

%% @doc
remove_task(ID, From, Reason, State) ->
    case State of #{tasks := Tasks} ->
        case orddict:find(ID, Tasks) of
            {ok, _} ->
                % logger:info("[SPAWN-RESULT]: task=~p;node=~p~n", [ID, From]),
                lynkia_spawn_monitor:on(#lynkia_spawn_remove_event{
                    id = ID,
                    from = From,
                    reason = Reason,
                    queue = tasks
                }),
                maps:put(
                    tasks,
                    orddict:erase(ID, Tasks),
                    State
                );
            error -> State
        end
    end.

% Handle cast:

%% @doc
handle_cast(#message{header = Header, body = Body}, State) ->
    case Body of
        {return, ID, Result} ->
            Node = Header#header.src,
            gen_server:cast(?MODULE, {return, ID, Node, Result});
        {kill, ID} ->
            Node = Header#header.src,
            gen_server:cast(?MODULE, {kill, ID, Node});
        _ ->
            gen_server:cast(?MODULE, Body)
    end,
    {noreply, State};

%% @doc
handle_cast({schedule, Task}, State) ->
    case State of #{tasks := Tasks} ->
        ID = Task#task.id,
        case orddict:is_key(ID, Tasks) of
            true ->
                {noreply, State};
            false ->
                S1 = add_task(Task, State),
                S2 = add_to_queue(Task, S1),
                S3 = run_tasks(S2),
                {noreply, S3}
        end
    end;

%% @doc
handle_cast({return, ID, Node, Result}, State) ->
    case get_task(ID, State) of
        {ok, #task{
            callback = Callback,
            hops = Hops
        }} ->
            case Hops of
                [] ->
                    erlang:apply(Callback, [Result]);
                [Hop|_] ->
                    send(Hop, {return, ID, Result})
            end,
            S1 = remove_from_forwarded(ID, Node, return, State),
            S2 = remove_from_running(ID, Node, return, S1),
            S3 = remove_from_queue(ID, S2),
            S4 = remove_task(ID, Node, return, S3),
            S5 = run_tasks(S4),
            {noreply, S5};
        error ->
            {noreply, State}
    end;

%% @doc
handle_cast({kill, ID, Node}, State) ->
    S1 = remove_from_forwarded(ID, Node, kill, State),
    S2 = remove_from_running(ID, Node, kill, S1),
    S3 = remove_from_queue(ID, S2),
    S4 = remove_task(ID, Node, kill, S3),
    S5 = run_tasks(S4),
    {noreply, S5};

%% @doc
handle_cast({forward, N, Node}, State) ->
    Myself = lynkia_utils:myself(),
    case Node == Myself of
        true -> State;
        false -> {noreply, forward_tasks(N, Node, State)}
    end;

%% @doc
handle_cast(debug, State) ->
    case State of #{
        queue := Q,
        running_tasks := RunningTasks,
        forwarded_tasks := ForwardedTasks
    } ->
        ?PRINT("running_tasks=~p;forwarded_tasks=~p;queue=~p~n", [
            orddict:size(RunningTasks),
            orddict:size(ForwardedTasks),
            queue:len(Q)
        ]),
        ok
    end,
    {noreply, State};

%% @doc
handle_cast(Message, State) ->
    ?PRINT("Unknown message~p~n", [Message]),
    {noreply, State}.

% Call:

%% @doc
handle_call(_Request, _From, State) ->
    {noreply, State}.

% Info:

%% @doc
handle_info(write_log, State) ->
    case State of #{
        queue := Q,
        running_tasks := RunningTasks,
        forwarded_tasks := ForwardedTasks
    } ->
        logger:info("[SPAWN-QUEUE]: node=~p;running_tasks=~p;forwarded_tasks=~p;queue=~p~n", [
            lynkia_utils:myself(), 
            orddict:size(RunningTasks),
            orddict:size(ForwardedTasks),
            queue:len(Q)
        ])
    end,
    erlang:send_after(?LOG_INTERVAL, ?MODULE, write_log),
    {noreply, State};

%% @doc
handle_info(_Info, State) ->
    {noreply, State}.

% Terminate:

%% @doc
terminate(_Reason, State) ->
    case State of #{running_tasks := RunningTasks} ->
        L = orddict:from_list(RunningTasks),
        lists:foreach(fun({_, Pid}) ->
            kill(Pid)
        end, L)
    end.

% Helpers:

%% @doc
% Pid is a process
% The process Pid is killed
kill(Pid) ->
    case Pid of
        undefined -> {noreply};
        _ -> erlang:exit(Pid, kill)
    end.

% API:

%% @doc
%  Fun is a function
%       Args is a list of arguments for Fun
%       Callback is a function
% Create a task containing Fun, Args and Callback and schedule it
schedule(Fun, Args, Callback) ->
    Task = #task{
        id = erlang:unique_integer(),
        function = Fun,
        arguments = Args,
        callback = Callback
    },
    gen_server:cast(?MODULE, {schedule, Task}).

%% @doc
schedule(Fun, Args) ->
    Self = self(),
    schedule(Fun, Args, fun(Result) ->
        Self ! Result
    end),
    receive Results ->
        Results
    end.

%% @doc
forward(N, Node) ->
    gen_server:cast(?MODULE, {forward, N, Node}).

%% @doc
debug() ->
    gen_server:cast(?MODULE, debug).
