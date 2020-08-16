%%%-------------------------------------------------------------------
%% @doc MapReduce manager.
%% @author Julien Banken and Nicolas Xanthos
%% @end
%%%-------------------------------------------------------------------
-module(lynkia_mapreduce).
-behavior(gen_server).
-include("lynkia.hrl").

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-export([
    start_link/0,
    init/1,
    handle_cast/2,
    handle_call/3,
    handle_info/2
]).

% API:

-export([
    schedule/3,
    schedule/4,
    gc/0,
    debug/0
]).

%% @doc Generate an unique tuple composed of the name of the node and an unique id
%% {node_name, id}
generate_unique_id() ->
    case lasp_unique:unique() of {ok, ID} ->
        {lynkia_utils:myself(), ID}
    end.

%% @doc Broadcast Message to other nodes of the network
broadcast(Message) ->
    lynkia_broadcast:broadcast(lynkia_mapreduce, Message).

%% @doc Send messages to Leader or Observer. Transform the messages from one API to another. 
gen_propagator(ID, Callback) ->
    fun(Message) ->
        case Message of
            {notify, [Round, Pairs, Reduce, Options]} ->
                Interval = lynkia_config:get(mapreduce_broadcast_interval),
                case Round rem Interval of
                    0 ->
                        broadcast({notify, [
                            ID, Round, Pairs, Reduce, Options, Callback
                        ]});
                    _ ->
                        ok
                end;
            {return, [Result]} ->
                Pid = erlang:whereis(lynkia_mapreduce),
                Pid ! {return, [ID, Result]},
                broadcast({return, [ID, Result]});
            heartbeat ->
                broadcast({heartbeat, [ID]});
            _ -> ok
        end
    end.

%% @doc Start the gen_server
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Init the gen_server
init([]) ->
    {ok, #{
        timer => erlang:spawn(fun() -> ok end),
        running => orddict:new(),
        finished => orddict:new()
    }}.

%% @doc Schedule the garbage collector
schedule_gc(State) ->
    case maps:find(timer, State) of
        {ok, Timer} ->
            case erlang:is_process_alive(Timer) of
                true -> State;
                false ->
                    State#{
                        timer => erlang:spawn(fun() ->
                            Delay = lynkia_config:get(mapreduce_gc_interval),
                            timer:sleep(Delay),
                            gc()
                        end)
                    }
            end;
        error -> 
            State#{
                timer => erlang:spawn(fun() ->
                    Delay = lynkia_config:get(mapreduce_gc_interval),
                    timer:sleep(Delay),
                    gc()
                end)
            }
    end.

%% @doc Add an Entry = {Pid, Callback} to the state in running
%% Pid is the process id of a Leader or an Observer
add_to_running(State, ID, Entry) ->
    S1 = schedule_gc(State),
    case S1 of #{running := Running} ->
        S1#{
            running => orddict:store(ID, Entry, Running)
        }
    end.

% Handle cast:

%% @doc Handle the message schedule. Start a new MapReduce and the current node is the leader
handle_cast({schedule, [Adapters, Reduce, Options, Callback]}, State) ->
    ID = generate_unique_id(),
    case lynkia_mapreduce_map:start(Adapters, Options) of
        {ok, Pairs} ->
            Data = [0, Pairs, Reduce, Options],
            Pid = erlang:spawn(fun() ->
                lynkia_mapreduce_leader:start(Data, gen_propagator(ID, Callback))
            end),
            {noreply, add_to_running(State, ID, #{
                pid => Pid,
                callback => Callback
            })}
    end;

%% @doc Handle the message gc. Start the garbage collector
handle_cast(gc, State) ->
    case State of #{running := Running, finished := Finished} ->
        TTL = lynkia_config:get(mapreduce_ttl),
        FilteredFinished = orddict:filter(fun(_Key, Value) ->
            lynkia_utils:now() - maps:get(timestamp, Value) < TTL
        end, Finished),
        case orddict:is_empty(Running) and orddict:is_empty(FilteredFinished) of
            true ->
                {noreply, State#{
                    finished => []
                }};
            false ->
                S1 = schedule_gc(State),
                S2 = S1#{
                    finished => FilteredFinished
                },
                {noreply, S2}
        end
    end;

%% @doc
handle_cast(debug, State) ->
    io:format("State=~p~n", [State]),
    {noreply, State};

%% @doc
handle_cast(_Request, State) ->
    io:format("Mapreduce: Unknown message~n"),
    {noreply, State}.

% Handle call:

%% @doc
handle_call(Request, _From, State) ->
    io:format("Call=~p~n", [Request]),
    {reply, ok, State}.

% Handle info:

%% @doc Handle the notify message
handle_info({notify, [ID, Round, Pairs, Reduce, Options, Callback]}, State) ->
    case State of #{running := Running, finished := Finished} ->
        case orddict:find(ID, Running) of
            {ok, #{pid := Pid}} ->
                Pid ! {notify, Round, Pairs},
                {noreply, State};
            _ ->
                case orddict:find(ID, Finished) of
                    {ok, _Result} ->
                        % TODO: Return the result ?
                        {noreply, State};
                    _ ->
                        Data = [Round, Pairs, Reduce, Options],
                        Pid = erlang:spawn(fun() ->
                            lynkia_mapreduce_observer:start(Data, gen_propagator(ID, Callback))
                        end),
                        {noreply, add_to_running(State, ID, #{
                            pid => Pid,
                            callback => Callback
                        })}
                end
        end
    end;

%% @doc Return the result of the MapReduce
handle_info({return, [ID, Result]}, State) ->
    case State of #{running := Running, finished := Finished} ->
        case orddict:find(ID, Running) of
            {ok, #{pid := Pid, callback := Callback}} ->
                Pid ! stop,
                erlang:apply(Callback, [Result]),
                {noreply, State#{
                    running => orddict:erase(ID, Running),
                    finished => orddict:store(ID, #{
                        timestamp => lynkia_utils:now(),
                        result => Result
                    }, Finished)
                }};
            _ ->
                {noreply, State}
        end
    end;

%% @doc Handle the heartbeat message
handle_info({heartbeat, [ID]}, State) ->
    case State of #{running := Running} ->
        case orddict:find(ID, Running) of
            {ok, #{pid := Pid}} ->
                Pid ! heartbeat;
            _ -> ok
        end,
        {noreply, State}
    end;

%% @doc
handle_info(debug, State) ->
    io:format("State=~p~n", [State]),
    {noreply, State};

%% @doc
handle_info(Message, State) ->
    io:format("Info=~p~n", [Message]),
    {noreply, State}.

% API:

%% @doc Schedule a new MapReduce
schedule(Adapters, Reduce, Callback) ->
    Options = #options{
        max_round = lynkia_config:get(mapreduce_max_round),
        max_batch_size = lynkia_config:get(mapreduce_max_batch_size),
        timeout = lynkia_config:get(mapreduce_round_timeout)
    },
    schedule(Adapters, Reduce, Options, Callback).

%% @doc Schedule a new MapReduce
schedule(Adapters, Reduce, Options, Callback) ->
    gen_server:cast(?MODULE, {schedule,
        [Adapters, Reduce, Options, Callback]
    }).

%% @doc Start the garbage collector
gc() ->
    % io:format("Starting the garbage collection~n"),
    gen_server:cast(?MODULE, gc).

%% @doc Print the state of the gen_server
debug() ->
    gen_server:cast(?MODULE, debug).

% ---------------------------------------------
% EUnit tests:
% ---------------------------------------------

-ifdef(TEST).

map_reduce_1_test() ->

    lynkia_sup:start_link(),

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

    Options = #options{
        max_round = 10,
        max_batch_size = 10,
        timeout = 3000
    },

    Self = self(),
    schedule(Adapters, Reduce, Options, fun(Result) ->
        Self ! Result
    end),

    receive {ok, OutputPairs} ->
        ?assertEqual(
            lists:sort(OutputPairs),
            lists:sort([
                {"Belgium", 15},
                {"France", 14},
                {"Spain", 18},
                {"Greece", 20}
            ])
        )
    end,
    ok.

map_reduce_2_test() ->

    lasp_sup:start_link(),

    IVar = {<<"documents">>, state_gset},
    lasp:bind(IVar, {state_gset, [
        "These are my cats",
        "The cats are over there",
        "I love cats"
    ]}),
    lasp:read(IVar, {cardinality, 3}),

    Adapters = [
        {lynkia_mapreduce_adapter_lasp, [
            {IVar, fun(Value) -> [Value] end}
        ]}
    ],

    Reduce = fun(Key, Values) ->
        [{Key, lists:sum(Values)}]
    end,

    Options = #options{
        max_round = 10,
        max_batch_size = 10,
        timeout = 3000
    },

    Self = self(),
    schedule(Adapters, Reduce, Options, fun(Result) ->
        Self ! Result
    end),

    receive {ok, OutputPairs} ->
        ?assertEqual(OutputPairs, [
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
    end,
    ok.

-endif.

% To launch the tests:
% rebar3 eunit --module=lynkia_mapreduce