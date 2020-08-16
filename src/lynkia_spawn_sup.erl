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

%% @doc Start the supervisor
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

% Supervisor:

%% @doc Initialize the supervisor
init([]) ->
    SupFlags = #{
        strategy => one_for_all,
        intensity => 1,
        period => 5
    },
    Module = lynkia_config:get(task_distribution_strategy),
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
    {ok, {SupFlags, ChildSpecs}}.