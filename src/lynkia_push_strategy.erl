%%%-------------------------------------------------------------------
%% @doc Implementation of the push strategy for the task model (lynkia_spawn).
%% @author Julien Banken and Nicolas Xanthos
%% @end
%%%-------------------------------------------------------------------

-module(lynkia_push_strategy).
-behaviour(gen_server).
-include("lynkia.hrl").

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
        number_of_tasks => 0
    }}.

% Add event :

%% @doc
handle_cast({on, #lynkia_spawn_add_event{queue = tasks}}, State) ->
    case State of #{number_of_tasks := N} ->
        case N > lynkia_config:get(forwarding_threshold) of
            false -> ok;
            true ->
                Neighbors = lynkia_utils:get_neighbors(),
                case lynkia_utils:choose(Neighbors) of
                    {ok, Node} ->
                        lynkia_spawn:forward(1, Node);
                    error -> ok
                end
        end,
        {noreply, State#{
            number_of_tasks => N + 1
        }}
    end;

% Remove event :

%% @doc
handle_cast({on, #lynkia_spawn_remove_event{queue = tasks}}, State) ->
    case State of #{number_of_tasks := N} ->
        {noreply, State#{
            number_of_tasks => N - 1
        }}
    end;

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

% API:

%% @doc
on(Event) ->
    gen_server:cast(?MODULE, {on, Event}).

%% @doc
debug() ->
    gen_server:cast(?MODULE, debug).
