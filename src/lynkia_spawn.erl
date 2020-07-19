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

% @pre -
% @post -
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

% @pre -
% @post -
init([]) ->
    erlang:send_after(?LOG_INTERVAL, ?MODULE, write_log),
    {ok, #{
        tasks => orddict:new(),
        queue => queue:new(),
        running_tasks => orddict:new(),
        forwarded_tasks => orddict:new()
    }}.

% @pre -
% @post -
get_task(ID, State) ->
    Tasks = maps:get(tasks, State),
    orddict:find(ID, Tasks).

% @pre -
% @post -
add_task(Task, State) ->
    ID = Task#task.id,
    maps:update_with(tasks, fun(Tasks) ->
        % print(State),
        orddict:store(ID, Task, Tasks)
    end, State).

% @pre -
% @post -
add_to_queue(Task, State) ->
    ID = Task#task.id,
    maps:update_with(queue, fun(Q) ->
        % print(State),
        queue:in(ID, Q)
    end, State).

% @pre -
% @post -
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

% @pre -
% @post -
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
                {'EXIT', _Parent, Reason} ->
                    Term = {return, ID, Myself, killed},
                    gen_server:cast(?MODULE, Term)
            after ?TIMEOUT ->
                erlang:exit(Pid, shutdown),
                Term = {return, ID, Myself, timeout},
                gen_server:cast(?MODULE, Term)
            end
        end)
    end.

% @pre -
% @post -
add_to_running(Task, State) ->
    maps:update_with(running_tasks, fun(RunningTasks) ->
        % print(State),
        ID = Task#task.id,
        Myself = lynkia_utils:myself(),
        lynkia_spawn_monitor:on_schedule(Myself, ID),
        Pid = execute_function(Task),
        orddict:store(ID, Pid, RunningTasks)
    end, State).

% @pre -
% @post -
add_to_forwarded(Node, Task, State) ->
    ID = Task#task.id,
    maps:update_with(forwarded_tasks, fun(ForwardedTasks) ->
        % print(State),
        orddict:store(ID, Node, ForwardedTasks)
    end, State).

% @pre -
% @post -
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

% @pre -
% @post -
run_tasks(State) ->
    case State of
        #{queue := Q, running_tasks := RunningTasks} ->
            N = ?MAX_RUNNING - orddict:size(RunningTasks),
            run_task(N, Q, State)
    end.

% @pre -
% @post -
is_forwarded(Task, State) ->
    case State of #{forwarded_tasks := ForwardedTasks} ->
        ID = Task#task.id,
        orddict:is_key(ID, ForwardedTasks)
    end.

% @pre -
% @post -
forward_task(N, Q, State) when N > 0 ->
    case queue:out_r(Q) of
        {empty, _} ->
            State;
        {{value, ID}, Queue} ->
            case get_task(ID, State) of {ok, Task} ->
                case is_forwarded(Task, State) of
                    true -> State;
                    false ->
                        Myself = lynkia_utils:myself(),
                        Hops = Task#task.hops,
                        case lynkia_spawn_monitor:choose_node(Hops) of
                            Node when Node == Myself ->
                                State;
                            Node ->
                                lynkia_spawn_monitor:on_schedule(Node, ID),
                                send(Node, {schedule, Task#task{
                                    hops = [lynkia_utils:myself()|Task#task.hops]
                                }}),
                                S1 = add_to_forwarded(Node, Task, State),
                                forward_task(N - 1, Queue, S1)
                        end
                end
            end
    end;
forward_task(_N, _Q, State) -> State.

% @pre -
% @post -
forward_tasks(State) ->
    case State of #{queue := Q} ->
        N = queue:len(Q) - ?MAX_SCHEDULE,
        forward_task(N, Q, State)
    end.

% @pre -
% @post -
remove_from_running(ID, State) ->
    case State of #{running_tasks := RunningTasks} ->
        case orddict:find(ID, RunningTasks) of
            {ok, Pid} ->
                kill(Pid),
                maps:update(
                    running_tasks,
                    orddict:erase(ID, RunningTasks),
                    State
                );
            error -> State
        end
    end.

% @pre -
% @post -
remove_from_forwarded(ID, State) ->
    case State of #{forwarded_tasks := ForwardedTasks} ->
        case orddict:is_key(ID, ForwardedTasks) of
            true ->
                maps:update(
                    forwarded_tasks,
                    orddict:erase(ID, ForwardedTasks),
                    State
                );
            false -> State
        end
    end.

% @pre -
% @post -
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

% @pre -
% @post -
remove_task(ID, State) ->
    case State of #{tasks := Tasks} ->
        maps:put(
            tasks,
            orddict:erase(ID, Tasks),
            State
        )
    end.

% @pre -
% @post -
get_worker(ID, State) ->
    case State of #{forwarded_tasks := ForwardedTasks} ->
        orddict:find(ID, ForwardedTasks)
    end.

% @pre -
% @post -
print(State) ->
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
    end.

% =============================================
% Handle cast:
% =============================================

% @pre -
% @post -
handle_cast(#message{header = Header, body = Body}, State) ->
    case Body of
        {return, ID, Result} ->
            Node = Header#header.src,
            gen_server:cast(?MODULE, {return, ID, Node, Result});
        _ ->
            gen_server:cast(?MODULE, Body)
    end,
    {noreply, State};

% @pre -
% @post -
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
                S4 = forward_tasks(S3),
                {noreply, S4}
        end
    end;

% @pre -
% @post -
handle_cast({return, ID, Node, Result}, State) ->

    case lynkia_utils:myself() of
        Myself when Myself == Node ->
            % ?PRINT("Returning: ID=~p Result=~p~n", [ID, Result]),
            lynkia_spawn_monitor:on_return(Myself, ID),
            case get_worker(ID, State) of
                {ok, Worker} ->
                    send(Worker, {kill, ID}),
                    lynkia_spawn_monitor:on_delete(Worker, ID);
                error -> ok
            end;
        Myself ->
            % ?PRINT("Receiving from ~p: ID=~p Result=~p~n", [Node, ID, Result]),
            lynkia_spawn_monitor:on_return(Node, ID),
            lynkia_spawn_monitor:on_delete(Myself, ID)
    end,

    case get_task(ID, State) of
        {ok, #task{
            callback = Callback,
            hops = Hops
        }} ->
            case Hops of
                [] -> erlang:apply(Callback, [Result]);
                [Hop|_] -> send(Hop, {return, ID, Result})
            end,
            S1 = remove_from_forwarded(ID, State),
            S2 = remove_from_running(ID, S1),
            S3 = remove_from_queue(ID, S2),
            S4 = remove_task(ID, S3),
            S5 = run_tasks(S4),
            {noreply, S5};
        error ->
            {noreply, State}
    end;

% @pre -
% @post -
handle_cast({kill, ID}, State) ->
    Myself = lynkia_utils:myself(),
    case get_worker(ID, State) of
        {ok, Worker} ->
            send(Worker, {kill, ID}),
            lynkia_spawn_monitor:on_delete(Worker, ID);
        error -> ok
    end,
    lynkia_spawn_monitor:on_delete(Myself, ID),
    S1 = remove_from_forwarded(ID, State),
    S2 = remove_from_running(ID, S1),
    S3 = remove_from_queue(ID, S2),
    S4 = remove_task(ID, S3),
    S5 = run_tasks(S4),
    {noreply, S5};

% @pre -
% @post -
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

% @pre -
% @post -
handle_cast(Message, State) ->
    ?PRINT("Unknown message~p~n", [Message]),
    {noreply, State}.

% Call:

% @pre -
% @post -
handle_call(_Request, _From, State) ->
    {noreply, State}.

% Info:

% @pre -
% @post -
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

% @pre -
% @post -
handle_info(_Info, State) ->
    {noreply, State}.

% Terminate:

% @pre -
% @post -
terminate(_Reason, State) ->
    case State of #{running_tasks := RunningTasks} ->
        L = orddict:from_list(RunningTasks),
        lists:foreach(fun({_, Pid}) ->
            kill(Pid)
        end, L)
    end.

% Helpers:

% @pre Pid is a process
% @post The process Pid is killed
kill(Pid) ->
    case Pid of
        undefined -> {noreply};
        _ -> erlang:exit(Pid, kill)
    end.

% API:

% @pre  Fun is a function
%       Args is a list of arguments for Fun
%       Callback is a function
% @post Create a task containing Fun, Args and Callback and schedule it
schedule(Fun, Args, Callback) ->
    Task = #task{
        id = erlang:unique_integer(),
        function = Fun,
        arguments = Args,
        callback = Callback
    },
    gen_server:cast(?MODULE, {schedule, Task}).

% @pre -
% @post -
schedule(Fun, Args) ->
    Self = self(),
    schedule(Fun, Args, fun(Result) ->
        Self ! Result
    end),
    receive Results ->
        Results
    end.

% @pre -
% @post -
send(Node, Message) ->
    partisan_peer_service:cast_message(Node, ?MODULE, #message{
        header = #header{
            src = lynkia_utils:myself()
        },
        body = Message
    }).

% @pre -
% @post -
debug() ->
    gen_server:cast(?MODULE, debug).
