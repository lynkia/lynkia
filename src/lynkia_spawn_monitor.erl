-module(lynkia_spawn_monitor).
-include("lynkia.hrl").

-export([
    on/1,
    debug/0
]).

% API:

%% @doc
on(Event) ->
    case lynkia_config:get(task_distribution_strategy) of
        {ok, Module} ->
            Module:on(Event)
    end.

%% @doc
debug() ->
    case lynkia_config:get(task_distribution_strategy) of
        {ok, Module} ->
            Module:debug()
    end.
