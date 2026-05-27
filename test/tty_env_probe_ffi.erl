-module(tty_env_probe_ffi).
-export([reset/0, record/1, seen/1]).

reset() ->
    put(tty_env_probe_seen, []),
    nil.

record(Name) ->
    put(tty_env_probe_seen, [Name | seen_names()]),
    nil.

seen(Name) ->
    lists:member(Name, seen_names()).

seen_names() ->
    case get(tty_env_probe_seen) of
        undefined -> [];
        Values -> Values
    end.
