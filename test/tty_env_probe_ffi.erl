-module(tty_env_probe_ffi).
-export([reset/0, record/1, seen/1]).

reset() ->
    put(tty_env_probe_seen, []),
    nil.

record(Name) ->
    Seen = case get(tty_env_probe_seen) of
        undefined -> [];
        Values -> Values
    end,
    put(tty_env_probe_seen, [Name | Seen]),
    nil.

seen(Name) ->
    Seen = case get(tty_env_probe_seen) of
        undefined -> [];
        Values -> Values
    end,
    lists:member(Name, Seen).
