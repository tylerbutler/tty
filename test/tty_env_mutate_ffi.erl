-module(tty_env_mutate_ffi).
-export([set_env/2, unset_env/1]).

set_env(Name, Value) ->
    os:putenv(to_charlist(Name), to_charlist(Value)),
    nil.

unset_env(Name) ->
    os:unsetenv(to_charlist(Name)),
    nil.

to_charlist(Bin) when is_binary(Bin) ->
    unicode:characters_to_list(Bin).
