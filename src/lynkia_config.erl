%%%-------------------------------------------------------------------
%% @doc Retrieve the configuration parameters given by the programmer.
%% @author Julien Banken and Nicolas Xanthos
%% @end
%%%-------------------------------------------------------------------
-module(lynkia_config).
-export([
    get/1,
    get/2,
    set/2
]).

%% @doc Retrieve the given environment variable
get(Key) ->
    case application:get_env(lynkia, Key) of
        {ok, Value} -> Value
    end.

%% @doc Retrieve the given environment variable
%% If the variable does not exist, the function will return the default value passed as parameter
get(Key, Default) ->
    case application:get_env(lynkia, Key) of
        {ok, Value} -> Value;
        _ -> Default
    end.

%% @doc Set the given environment variable to the given value
set(Key, Value) ->
    application:set_env(lynkia, Key, Value).