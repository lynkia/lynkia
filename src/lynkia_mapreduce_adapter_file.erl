%%%-----------------------------------------------------------------------------
%%% @doc 
%%%
%%% @author Julien Banken and Nicolas Xanthos
%%% @end
%%%-----------------------------------------------------------------------------
-module(lynkia_mapreduce_adapter_file).
-export([
    get_pairs/3
]).

%% @doc
get_pairs(Entries, _Options, Callback) ->
    Pairs = lists:flatmap(fun({Path, Map}) ->
        Lines = file_reader:readfile(Path),
        erlang:apply(Map, [Lines])
    end, Entries),
    erlang:apply(Callback, [Pairs]).