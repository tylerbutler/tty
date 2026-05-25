-module(tty_ffi).
-export([stdin_is_tty/0, stdout_is_tty/0, stderr_is_tty/0, get_env/1]).

stdin_is_tty()  -> tty_option_enabled(standard_io, stdin).
stdout_is_tty() -> tty_option_enabled(standard_io, stdout).
stderr_is_tty() -> tty_option_enabled(standard_io, stderr).

%% io:getopts/1 is available on OTP 26+. On OTP 26+ the standard_io device
%% reports per-stream TTY status via the stdin/stdout/stderr keys; the
%% standard_error device does NOT carry those keys, so all three queries
%% target standard_io. Known compatibility/runtime failures fall back to false
%% so Gleam's Bool result is total.
tty_option_enabled(Dev, Key) ->
    try io:getopts(Dev) of
        Opts when is_list(Opts) ->
            proplists:get_value(Key, Opts, false) =:= true;
        _ ->
            false
    catch
        error:badarg ->
            false;
        error:undef ->
            false
    end.

%% Returns {ok, Value} | {error, nil} to match Gleam's Result(String, Nil).
get_env(Name) when is_binary(Name) ->
    case os:getenv(unicode:characters_to_list(Name)) of
        false -> {error, nil};
        Value -> {ok, unicode:characters_to_binary(Value)}
    end.
