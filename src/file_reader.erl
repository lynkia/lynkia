%%%-----------------------------------------------------------------------------
%%% @doc This module contains functions to read different type of file.
%%%
%%% @author Julien Banken and Nicolas Xanthos
%%% @end
%%%-----------------------------------------------------------------------------
-module(file_reader).
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-export([
    readfile/1,
    read_csv/3,
    load_csv/2
]).

%% @doc Read a file
readfile(Path) ->
    case file:read_file(Path) of
        {ok, IOData} ->
            Binaries = binary:split(IOData, [<<"\n">>], [global]),
            lists:foldr(fun(Binary, Lines) ->
                Line = erlang:binary_to_list(Binary),
                case Line of [] -> Lines; _ -> [Line|Lines] end 
            end, [], Binaries);
        {error, _Reason} -> erlang:exit("Unvalid file path")
    end.

%% @doc
gen_tuple(Labels, Columns, Parser) ->
    L = lists:zip(Labels, Columns),
    lists:foldl(fun({Label, Column}, Tuple) ->
        Key = erlang:list_to_atom(Label),
        Value = erlang:apply(Parser, [Key, Column]),
        maps:put(Key, Value, Tuple)
    end, #{}, L).

%% @doc read a CSV file
read_csv(Path, Separator, Parser) ->
    Lines = readfile(Path),
    case Lines of
        [] -> [];
        [Header|Body] ->
            Labels = string:tokens(Header, Separator),
            lists:map(fun(Line) ->
                Columns = string:tokens(Line, Separator),
                gen_tuple(Labels, Columns, Parser)
            end, Body)
    end.

%% @doc
give_ids(Tuples) ->
    lists:foldl(fun(Tuple, {I, List}) ->
        {I + 1, [{I, Tuple}|List]}
    end, {0, []}, Tuples).

%% @doc Load CSV file
load_csv(Path, GSet) ->
    Separator = ";",
    Parser = fun(Label, Column) ->
        case Label of temperature ->
            erlang:list_to_integer(Column);
        _ -> Column end
    end,
    {N, Tuples} = give_ids(read_csv(Path, Separator, Parser)),
    lasp:bind(GSet, {state_gset, Tuples}),
    lasp:read(GSet, {cardinality, N}).

% ---------------------------------------------
% EUnit tests:
% ---------------------------------------------

-ifdef(TEST).

read_csv_test() ->
    Path = "dataset/test.csv",
    Separator = ";",
    Parser = fun(_, Column) -> Column end,
    ?assertEqual(read_csv(Path, Separator, Parser), [
        #{temperature => "15", country => "Belgium"},
        #{temperature => "14", country => "France"},
        #{temperature => "18", country => "Spain"},
        #{temperature => "20", country => "Greece"}
    ]).

-endif.

% To launch the tests:
% rebar3 eunit --module=file_reader