%%%-----------------------------------------------------------------------------
%%% @doc 
%%%
%%% @author Julien Banken and Nicolas Xanthos
%%% @end
%%%-----------------------------------------------------------------------------

-module(lynkia).
-export([
    spawn/2,
    spawn/3,
    mapreduce/3,
    mapreduce/4
]).

%% @doc Create a task containing Fun, Args and schedule it
-spec spawn(Fun :: function, Args :: []) -> ok.
spawn(Fun, Args) ->
    lynkia_spawn:schedule(Fun, Args).

%% @doc Create a task containing Fun, Args and Callback and schedule it
-spec spawn(Fun :: function, Args :: [], Callback :: function) -> ok.
spawn(Fun, Args, Callback) ->
    lynkia_spawn:schedule(Fun, Args, Callback).

%% @doc Start a MapReduce
-spec mapreduce(Adapters :: any, Reduce :: function, Callback :: function) -> ok.
mapreduce(Adapters, Reduce, Callback) ->
    lynkia_mapreduce:schedule(Adapters, Reduce, Callback).

%% @doc Start a MapReduce
-spec mapreduce(Adapters :: any, Reduce :: function, Option :: any, Callback :: function) -> ok.
mapreduce(Adapters, Reduce, Options, Callback) ->
    lynkia_mapreduce:schedule(Adapters, Reduce, Options, Callback).