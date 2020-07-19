-module(lynkia_config).
-export([
    get/1,
    get/2,
    set/2
]).

% @pre -
% @post -
get(Key) ->
    application:get_env(lynkia, Key).

% @pre -
% @post -
get(Key, Default) ->
    application:get_env(lynkia, Key, Default).

% @pre -
% @post -
set(Key, Value) ->
    application:set_env(lynkia, Key, Value).