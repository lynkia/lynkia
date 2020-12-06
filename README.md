# Lynkia 

<!-- What is Lynkia ? -->

Lynkia is a library to make large-scale computation on a peer-to-peer network composed of IoT devices. The library provides a MapReduce algorithm and a task model. These algorithms have been designed to tolerate faults and to operate on the extreme edge of a decentralized network.

**Disclaimer**: This project has been carried out within the framework of a master thesis at UCLouvain (Belgium :belgium:). You can get more information about the project by consulting the [wiki](https://github.com/lynkia/lynkia/wiki) or [our master thesis](https://dial.uclouvain.be/memoire/ucl/object/thesis:26489).

---

## Quick overview

### Peering

With Partisan, we can connect two devices:

```erlang
lynkia_utils:join('lynkia@hostname').
```

### Storing

With Lasp, the devices can share data by storing them in a CRDT. These variables will be replicated on each node. The nodes will then be able to update the variable independently. Lasp provides the guarantee that the state of the variables will eventually converge given that all update messages are eventually delivered.

In the following example, we can imagine that each device has a sensor and can measure the current temperature. At regular interval, each device can store its measure and its location in a new tuple `{room, temperature}`.

```erlang
lasp:update({<<"temperatures">>, state_gset}, {add, {kitchen, 18}}, self()).
```

### Processing

#### MapReduce

Lynkia comes with a MapReduce model that can be used to process data stored in the CRDT variables of Lasp. Lynkia will have the responsibility to coordinate the nodes and to handle node failures.

Example:

```erlang
Adapters = [
    {lynkia_mapreduce_adapter_lasp, [
        {"temperatures", fun(Tuple) ->
            case Tuple of
                {Room, Temperature} -> [{Room, erlang:list_to_integer(Temperature)}];
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

In this example, the query will compute the maximal temperature of each room.

#### Task model

The MapReduce model uses a task model that can be used independently. The task model will have the responsibility to distribute the workload of the node over its neighbors.

```erlang
Fun = fun() -> 
    42
end,
Callback = fun(Result) ->
    io:format("Result ~p~n", [Result]) % Print "Result 42"
end,
lynkia:spawn(Fun, [], Callback).
```

In this example, the function `Fun` will be evaluated by the node itself or one of its neighbors. The function `Callback` will be called when the function `Fun` has been evaluated. The argument of the function `Callback` will correspond to the result of the function `Fun`.

## Guarantee

- Partition tolerance
- Fault tolerant (up to n - 1 failures)

## Installation

You will find in our [wiki](https://github.com/lynkia/lynkia/wiki/Getting-started) all the instructions to install the dev tools. We will also explain how to deploy the library on a [GRiSP](https://www.grisp.org/) board.

## Dependencies

- [Lasp](https://github.com/lasp-lang/lasp)
- [Partisan](https://github.com/lasp-lang/partisan)

## Resources

- [Doing large-scale computations on an Internet of Things network](https://dial.uclouvain.be/memoire/ucl/object/thesis:26489)
- [18th ACM SIGPLAN International Workshop on Erlang](https://www.info.ucl.ac.be/~pvr/LivingOnTheEdge.pdf)

## License

This software is licensed under the Apache 2.0 LICENSE.
