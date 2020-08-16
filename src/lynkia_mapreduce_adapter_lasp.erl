%%%-----------------------------------------------------------------------------
%%% @doc Adapter for CRDT variables.
%%%
%%% @author Julien Banken and Nicolas Xanthos
%%% @end
%%%-----------------------------------------------------------------------------
-module(lynkia_mapreduce_adapter_lasp).
-export([
    get_pairs/3
]).

%% @doc Generate key-value pairs from a CRDT variable
get_pairs(Entries, _Options, Callback) ->
    Pairs = lists:flatmap(fun({IVar, Map}) ->
        Values = lynkia_utils:query(IVar),
        lists:flatmap(fun(Value) ->
            erlang:apply(Map, [Value])
        end, Values)
    end, Entries),
    erlang:apply(Callback, [Pairs]).
