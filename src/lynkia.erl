-module(lynkia).
-export([
    spawn/2,
    spawn/3,
    mapreduce/3,
    mapreduce/4
]).

% @pre -
% @post -
spawn(Fun, Args) ->
    lynkia_spawn:schedule(Fun, Args).

% @pre -
% @post -
spawn(Fun, Args, Callback) ->
    lynkia_spawn:schedule(Fun, Args, Callback).

% @pre -
% @post -
mapreduce(Adapters, Reduce, Callback) ->
    lynkia_mapreduce:schedule(Adapters, Reduce, Callback).

% @pre -
% @post -
mapreduce(Adapters, Reduce, Options, Callback) ->
    lynkia_mapreduce:schedule(Adapters, Reduce, Options, Callback).