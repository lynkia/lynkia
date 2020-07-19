-module(lynkia_spawn_monitor).
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
    on_schedule/2,
    on_return/2,
    on_delete/2,
    get_average_response_times/1,
    choose_node/1,
    debug/0
]).

% @pre -
% @post -
init([]) ->
    {ok, #{
        logs => orddict:new(),
        response_times => orddict:new()
    }}.

% @pre -
% @post -
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

% @pre -
% @post -
handle_cast({on_schedule, Node, ID}, State) ->
    case State of #{ logs := Logs } ->
        Key = {Node, ID},
        Info = orddict:from_list([
            {Key, lynkia_utils:now()}
        ]),
        {noreply, State#{
            logs := orddict:merge(fun(_Key, _V1, V2) -> V2 end, Logs, Info)
        }}
    end;

% @pre -
% @post -
handle_cast({on_return, Node, ID}, State) ->
    case State of #{logs := Logs, response_times := ResponseTimes} ->
        Key = {Node, ID},
        case orddict:find(Key, Logs) of
            {ok, Timestamp} ->
                Now = lynkia_utils:now(),
                ResponseTime = Now - Timestamp,
                Measure = {Now, ResponseTime},
                ?PRINT("source=~p;destination=~p;timestamp=~p;response_time=~p~n", [
                    lynkia_utils:myself(),
                    Node,
                    Timestamp,
                    ResponseTime
                ]),
                {noreply, State#{
                    logs := orddict:erase(Key, Logs),
                    response_times := orddict:append(Node, Measure, ResponseTimes)
                }};
            error ->
                {noreply, State}
        end
    end;

% @pre -
% @post -
handle_cast({on_delete, Node, ID}, State) ->
    case State of #{logs := Logs} ->
        Key = {Node, ID},
        {noreply, State#{
            logs := orddict:erase(Key, Logs)
        }}
    end;

% @pre -
% @post -
handle_cast(debug, State) ->
    ?PRINT("State: ~p~n", [State]),
    {noreply, State};

% @pre -
% @post -
handle_cast(_Message, State) ->
    {noreply, State}.

% @pre -
% @post -
handle_call({get_average_response_time, Node}, _From, State) ->
    case State of #{response_times := ResponseTimes} ->
        case orddict:find(Node, ResponseTimes) of
            {ok, Measures} ->
                Now = lynkia_utils:now(),
                EstimatedResponseTime = get_estimated_response_time(Measures, Now),
                % ?PRINT("Average=~p~n", [AverageResponseTime]),
                % ?PRINT("Node=~p~n", [Node]),
                % ?PRINT("L=~p~n", [L]),
                {reply, EstimatedResponseTime, State};
            error ->
                {reply, 0, State}
        end
    end;

% @pre -
% @post -
handle_call(_Request, _From, State) ->
    {noreply, State}.

% @pre -
% @post -
handle_info(_Info, State) ->
    {noreply, State}.

% @pre -
% @post -
terminate(_Reason, _State) ->
    ok.

% Helpers:

% @pre -
% @post -
get_ema(Measures, T) ->
    Tau = 1,
    lists:foldl(fun({X, Y}, Average) ->
        Alpha = 1 - math:exp(-(T - X) / Tau),
        Average + Alpha * (Y - Average)
    end, 0, Measures).

% @pre -
% @post -
get_decay(Measure, T) ->
    case Measure of {X, Y} ->
        Lambda = 0.001,
        Dt = T - X,
        Y - (Y * math:exp(- Lambda * Dt))
    end.

% % @pre -
% % @post -
get_estimated_response_time([], T) -> 0;
get_estimated_response_time(Measures, T) ->
    case lists:last(Measures) of
        {X, Y} = Measure when X < T ->
            Ema = get_ema(Measures, T),
            Decay = get_decay(Measure, T),
            Ema - Decay;
        _ ->
            get_estimated_response_time(lists:takewhile(fun({X, _Y}) -> X < T end, Measures), T)
    end.

% @pre -
% @post -
remove_old_measures(Measures, Now, Lifespan) ->
    lists:dropwhile(fun({X, _Y}) ->
        Now - X > Lifespan
    end, Measures).

% API:

% @pre -
% @post -
on_schedule(Node, ID) ->
    gen_server:cast(?MODULE, {on_schedule, Node, ID}).

% @pre -
% @post -
on_return(Node, ID) ->
    gen_server:cast(?MODULE, {on_return, Node, ID}).

% @pre -
% @post -
on_delete(Node, ID) ->
    gen_server:cast(?MODULE, {on_delete, Node, ID}).

% @pre -
% @post -
get_average_response_time(Node) ->
    gen_server:call(?MODULE, {get_average_response_time, Node}).

% @pre -
% @post -
get_average_response_times(Nodes) ->
    orddict:from_list(
        lists:map(fun(Node) ->
            {Node, get_average_response_time(Node)}
        end, Nodes)
    ).

% @pre  Hops is the list of nodes through which the task has passed (hops)
% @post Choose a node among the neighbors except the nodes in Blacklist
choose_node(Hops) ->

    Myself = lynkia_utils:myself(),
    Blacklist = [Myself|Hops],
    {ok, Members} = partisan_peer_service:members(),
    
    Nodes = lists:filter(fun(Member) ->
        not lists:member(Member, Blacklist)
    end, Members),

    case Nodes of
        [] ->
            Myself;
        _ ->
            Orddict = get_average_response_times(Nodes),
            {Node, _} = orddict:fold(fun(K1, V1, Min) ->
                case Min of
                    undefined -> {K1, V1};
                    {_K2, V2} when V1 < V2 -> {K1, V1};
                    _ -> Min
                end
            end, undefined, Orddict),
            ?PRINT("Estimated response times = ~p~n", [Orddict]),
            ?PRINT("Chosen node = ~p~n", [Node]),
            ?PRINT("~n", []),
            Node
    end.

% @pre -
% @post -
debug() ->
    gen_server:cast(?MODULE, debug).

% ---------------------------------------------
% EUnit tests:
% ---------------------------------------------

-ifdef(TEST).

% @pre -
% @post -
ema_test() ->
    Xs = [
        0, 50, 100, 150, 200, 250, 300, 350, 400, 450,
        500, 550, 600, 650, 700, 750, 800, 850, 900, 950
    ],
    Ys = [
        0, 50, 100, 150, 200, 250, 300, 350, 400, 450,
        500, 550, 600, 650, 700, 750, 800, 850, 900, 950
    ],
    Measures = lists:zip(Xs, Ys),
    Epsilon = 1,
    ?assert(erlang:abs(get_estimated_response_time(Measures, 996) - 907) =< Epsilon),
    ?assert(erlang:abs(get_estimated_response_time(Measures, 574) - 537) =< Epsilon),
    ?assert(erlang:abs(get_estimated_response_time(Measures, 70) - 49) =< Epsilon),
    ?assert(erlang:abs(get_estimated_response_time(Measures, 700) - 618) =< Epsilon),
    ok.

-endif.

% To launch the tests:
% rebar3 eunit --module=lynkia_spawn_monitor