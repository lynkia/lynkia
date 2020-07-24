%%%-----------------------------------------------------------------------------
%%% @doc 
%%%
%%% @author Julien Banken and Nicolas Xanthos
%%% @end
%%%-----------------------------------------------------------------------------
-module(lynkia_utils).
-export([
    join/1,
    myself/0,
    members/0,
    get_neighbors/0,
    repeat/2,
    query/1,
    now/0
]).

%% @doc
myself() ->
    Manager = partisan_peer_service:manager(),
    case Manager:myself() of
        #{name := Name} -> Name
    end.

%% @doc
join(Name) ->
    partisan_peer_service:join(Name).

%% @doc
members() ->
    partisan_peer_service:members().

%% @doc
get_neighbors() ->
    case members() of {ok, Members} ->
        Name = myself(),
        Members -- [Name]
    end.

%% @doc
repeat(N, CallBack) ->
    repeat(0, N, CallBack).
repeat(K, N, CallBack) when N > 0 ->
    CallBack(K),
    repeat(K + 1, N - 1, CallBack);
repeat(_, N, _) when N =< 0 -> ok.

%% @doc
query(ID) ->
    {ok, Set} = lasp:query(ID) ,
    sets:to_list(Set).

%% @doc
now() ->
    erlang:system_time(millisecond).