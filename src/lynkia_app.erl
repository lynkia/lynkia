%%%-----------------------------------------------------------------------------
%%% @doc 
%%%
%%% @author Julien Banken and Nicolas Xanthos
%%% @end
%%%-----------------------------------------------------------------------------

-module(lynkia_app).
-behaviour(application).
-export([
    start/2,
    stop/1
]).

%% @doc
start(_StartType, _StartArgs) ->
    case application:ensure_all_started(lasp) of
        {ok, _} -> lynkia_sup:start_link()
    end.

%% @doc
stop(_State) ->
    ok.
