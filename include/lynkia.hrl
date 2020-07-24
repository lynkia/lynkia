-define(DEBUG, true).

-define(TIMEOUT, 5000).
-define(MAX_RUNNING, 1).
-define(FORWARDING_THRESHOLD, 50).
-define(LOG_INTERVAL, 100).

-define(PRINT(Pattern, Args),
    case ?DEBUG of
        true -> io:format(Pattern, Args);
        false -> ok
    end
).

-record(lynkia_spawn_add_event, {
    id :: any(), % Which task ?
    target :: term(), % Who will execute the task ?
    queue :: tasks | running | forwarded
}).

-record(lynkia_spawn_remove_event, {
    id :: any(), % Which task ?
    from :: term(), % Who computed the result ?
    reason :: return | kill, % Why the task has been removed
    queue :: tasks | running | forwarded % Which queue ?
}).

-record(options, {
    max_round :: integer(),
    max_batch_size :: integer(),
    timeout :: integer()
}).