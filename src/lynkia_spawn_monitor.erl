%%%-------------------------------------------------------------------
%% @doc Event dispatcher of the task model.
%% @author Julien Banken and Nicolas Xanthos
%% @end
%%%-------------------------------------------------------------------

-module(lynkia_spawn_monitor).
-include("lynkia.hrl").

-export([
    on/1,
    debug/0
]).

% API:

%% @doc Forward the event to the module set in the configuration file (see task_distribution_strategy)
on(Event) ->
    Module = lynkia_config:get(task_distribution_strategy),
    Module:on(Event).

%% @doc Ask the module set in the configuration file to print debug messages (see task_distribution_strategy)
debug() ->
    Module = lynkia_config:get(task_distribution_strategy),
    Module:debug().
