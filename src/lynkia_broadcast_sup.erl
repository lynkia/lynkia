%%%-------------------------------------------------------------------
%% @doc Lynkia_broadcast supervisor.
%% @author Julien Banken and Nicolas Xanthos
%% @end
%%%-------------------------------------------------------------------

-module(lynkia_broadcast_sup).
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