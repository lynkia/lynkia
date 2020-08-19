# Lynkia

<!-- What is Lynkia ? -->

Lynkia is a library to make large-scale computation on a peer-to-peer network composed of IoT devices. The library provides a resilient MapReduce algorithm and a task model designed to run on the extreme edge of the network.

## Assumptions

- Dynamic membership
- Unreliable network
- Limited computing power
- Limited storage

## Features

- Modular
- Configurable

## Overview

### MapReduce

```erlang
Adapters = [
    {lynkia_mapreduce_adapter_csv, [
        {"dataset/test.csv", fun(Tuple) ->
            case Tuple of #{
                temperature := Temperature,
                country := Country
            } -> [{Country, erlang:list_to_integer(Temperature)}];
            _ -> [] end
        end}
    ]}
],

Reduce = fun(Key, Values) ->
    [{Key, lists:max(Values)}]
end,

lynkia:mapreduce(Adapters, Reduce, fun(Result) ->
    case Result of {ok, Pairs} ->
        io:format("Pairs=~p~n", [Pairs])
    end
end).
```

This query will compute the maximal tempertature of each country.

### Task model

```erlang
lynkia:spawn(fun() -> 
    42
end, [], fun(Result) ->
    io:format("Result ~p~n", [Result]) % Print "Result 42"
end)
```

## Installation

You will find in our [wiki](https://github.com/lynkia/lynkia/wiki/Getting-started) all the instructions to install the dev tools. We will also explain how to deploy the library on a [GRiSP](https://www.grisp.org/) board.

## License

This software is licensed under the Apache 2.0 LICENSE.
