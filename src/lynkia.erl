%%%-----------------------------------------------------------------------------
%%% @doc This module exposes the API of Lynkia.
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

%% @doc Schedule a function in the task model. The call is synchronous
spawn(Fun, Args) ->
    lynkia_spawn:schedule(Fun, Args).

%% @doc Schedule a function in the task model. The call is asynchronous
spawn(Fun, Args, Callback) ->
    lynkia_spawn:schedule(Fun, Args, Callback).

%% @doc Start a MapReduce
mapreduce(Adapters, Reduce, Callback) ->
    lynkia_mapreduce:schedule(Adapters, Reduce, Callback).

%% @doc Start a MapReduce with options overwriting the default options
mapreduce(Adapters, Reduce, Options, Callback) ->
    lynkia_mapreduce:schedule(Adapters, Reduce, Options, Callback).