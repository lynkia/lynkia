-module(lynkia_spawn_sup).
-behaviour(supervisor).
-export([
    init/1
]).
-export([
    start_link/0
]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

% Supervisor:

init([]) ->
    SupFlags = #{
        strategy => one_for_one,
        intensity => 1,
        period => 5
    },
    ChildSpecs = [
        #{
            id => lynkia_spawn,
            start => {lynkia_spawn, start_link, []},
            restart => permanent
        },
        #{
            id => lynkia_spawn_monitor,
            start => {lynkia_spawn_monitor, start_link, []},
            restart => permanent
        }
    ],
    {ok, {SupFlags, ChildSpecs}}.