%%%-------------------------------------------------------------------
%% @doc lynkia_spawn supervisor.
%% @author Julien Banken and Nicolas Xanthos
%% @end
%%%-------------------------------------------------------------------
-module(lynkia_spawn_sup).
-behaviour(supervisor).
-export([
    init/1
]).
-export([
    start_link/0
]).

%% @doc
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

% Supervisor:

%% @doc
init([]) ->
    SupFlags = #{
        strategy => one_for_all,
        intensity => 1,
        period => 5
    },
    case lynkia_config:get(task_distribution_strategy) of
        {ok, Module} ->
            ChildSpecs = [
                #{
                    id => lynkia_spawn,
                    start => {lynkia_spawn, start_link, []},
                    restart => permanent
                },
                #{
                    id => Module,
                    start => {Module, start_link, []},
                    restart => permanent
                }
            ],
            {ok, {SupFlags, ChildSpecs}}
    end.