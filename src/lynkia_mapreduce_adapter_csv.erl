%%%-----------------------------------------------------------------------------
%%% @doc Adapter for CSV files.
%%%
%%% @author Julien Banken and Nicolas Xanthos
%%% @end
%%%-----------------------------------------------------------------------------
-module(lynkia_mapreduce_adapter_csv).
-export([
    get_pairs/3
]).

%% @doc Generate key-value pairs from a csv file
%% Callback - Function to call all pairs have been produced
get_pairs(Entries, _Options, Callback) ->
    Separator = ";",
    Parser = fun(_, Column) -> Column end,
    Pairs = lists:flatmap(fun({Path, Map}) ->
        Tuples = file_reader:read_csv(Path, Separator, Parser),
        lists:flatmap(fun(Tuple) ->
            erlang:apply(Map, [Tuple])
        end, Tuples)
    end, Entries),
    erlang:apply(Callback, [Pairs]).
