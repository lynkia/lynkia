%%%-------------------------------------------------------------------
%% @doc lynkia top level supervisor.
%% @author Julien Banken and Nicolas Xanthos
%% @end
%%%-------------------------------------------------------------------
-module(lynkia_sup).
-behaviour(supervisor).
-export([
    init/1,
    start_link/0
]).

-define(SERVER, ?MODULE).

%% @doc
start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%% @doc
init([]) ->
    SupFlags = #{
        strategy => one_for_all,
        intensity => 0,
        period => 1
    },
    ChildSpecs = [
        #{
            id => lynkia_spawn_sup,
            start => {lynkia_spawn_sup, start_link, []},
            restart => transient,
            type => supervisor
        },
        #{
            id => lynkia_broadcast_sup,
            start => {lynkia_broadcast_sup, start_link, []},
            restart => transient,
            type => supervisor
        },
        #{
            id => lynkia_mapreduce,
            start => {lynkia_mapreduce, start_link, []},
            restart => transient,
            type => worker
        }
    ],
    {ok, {SupFlags, ChildSpecs}}.