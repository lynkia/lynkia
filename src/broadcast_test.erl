-module(broadcast_test).
-export([
    test/0
]).

% broadcast_test:test().

% @pre -
% @post -
test() ->
    % ServerRef = broadcast_receiver,
    ServerRef = lynkia_mapreduce,
    lynkia_utils:repeat(20, fun(K) ->
        timer:sleep(500),
        Message = "Message n°" ++ erlang:integer_to_list(K) ++ "~n",
        io:format("Sending message: ~p~n", [Message]),
        lynkia_broadcast:broadcast(ServerRef, Message)
    end).