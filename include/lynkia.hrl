-define(DEBUG, true).

-define(TIMEOUT, 5000).
-define(MAX_RUNNING, 5).
-define(MAX_SCHEDULE, 450).
-define(LOG_INTERVAL, 100).

-define(PRINT(Pattern, Args),
    case ?DEBUG of
        true -> io:format(Pattern, Args);
        false -> ok
    end
).

-record(options, {
    max_round :: integer(),
    max_batch_size :: integer(),
    timeout :: integer()
}).