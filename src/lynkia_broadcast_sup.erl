-module(lynkia_broadcast_sup).
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
            id => lynkia_broadcast,
            start => {lynkia_broadcast, start_link, []},
            restart => permanent,
            type => worker
        }
    ],
    {ok, {SupFlags, ChildSpecs}}.