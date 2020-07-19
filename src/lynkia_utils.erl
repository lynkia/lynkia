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

% @pre -
% @post -
myself() ->
    Manager = partisan_peer_service:manager(),
    case Manager:myself() of
        #{name := Name} -> Name
    end.

% @pre -
% @post -
join(Name) ->
    partisan_peer_service:join(Name).

% @pre -
% @post -
members() ->
    partisan_peer_service:members().

% @pre -
% @post -
get_neighbors() ->
    case members() of {ok, Members} ->
        Name = myself(),
        Members -- [Name]
    end.

% @pre -
% @post -
repeat(N, CallBack) ->
    repeat(0, N, CallBack).
repeat(K, N, CallBack) when N > 0 ->
    CallBack(K),
    repeat(K + 1, N - 1, CallBack);
repeat(_, N, _) when N =< 0 -> ok.

% @pre -
% @post -
query(ID) ->
    {ok, Set} = lasp:query(ID) ,
    sets:to_list(Set).

% @pre -
% @post -
now() ->
    erlang:system_time(millisecond).