%%%-------------------------------------------------------------------
%% @doc lynkia public API
%% @end
%%%-------------------------------------------------------------------

-module(lynkia_app).
-behaviour(application).
-export([
    start/2,
    stop/1
]).

% @pre -
% @post -
start(_StartType, _StartArgs) ->
    case application:ensure_all_started(lasp) of
        {ok, _} -> lynkia_sup:start_link()
    end.

% @pre -
% @post -
stop(_State) ->
    ok.
