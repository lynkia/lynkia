%%%-------------------------------------------------------------------
%% @doc
%% @author Julien Banken and Nicolas Xanthos
%% @end
%%%-------------------------------------------------------------------
-module(lynkia_config).
-export([
    get/1,
    get/2,
    set/2
]).

%% @doc
get(Key) ->
    application:get_env(lynkia, Key).

%% @doc
get(Key, Default) ->
    application:get_env(lynkia, Key, Default).

%% @doc
set(Key, Value) ->
    application:set_env(lynkia, Key, Value).