-module(tty_ffi).
-export([
    stdin_is_tty/0,
    stdout_is_tty/0,
    stderr_is_tty/0,
    get_env/1,
    query_background/2
]).
%% Exported for contract testing only; not used from Gleam.
-export([env_value_to_result/1, query_background_with_ops/3]).

-define(OSC_11_QUERY, <<27, "]11;?", 7>>).
-define(MAX_QUERY_TIMEOUT_MS, 100).

stdin_is_tty()  -> tty_option_enabled(standard_io, stdin).
stdout_is_tty() -> tty_option_enabled(standard_io, stdout).
stderr_is_tty() -> tty_option_enabled(standard_io, stderr).

%% io:getopts/1 is available on OTP 26+. On OTP 26+ the standard_io device
%% reports per-stream TTY status via the stdin/stdout/stderr keys; the
%% standard_error device does NOT carry those keys, so all three queries
%% target standard_io. Any failure to read options (missing function on older
%% OTP, badarg, a closed/terminated I/O server at shutdown, etc.) falls back to
%% false so Gleam's Bool result is total. The catch-all is deliberate: the
%% public contract is "returns false when TTY status cannot be determined", so
%% no exception class should ever escape this function.
tty_option_enabled(Dev, Key) ->
    try io:getopts(Dev) of
        Opts when is_list(Opts) ->
            option_enabled(Opts, Key);
        _ ->
            false
    catch
        _:_ ->
            false
    end.

%% Returns {ok, RawResponse} | {error, nil}. The stream atoms are the Erlang
%% representation of tty.Stream's nullary constructors.
query_background(Stream, TimeoutMs) ->
    try
        Lock = {{?MODULE, background_query}, self()},
        case global:trans(
            Lock,
            fun() ->
                query_background_with_ops(Stream, TimeoutMs, default_query_ops())
            end,
            [node()],
            0
        ) of
            aborted -> {error, nil};
            Result -> Result
        end
    catch
        _:_ -> {error, nil}
    end.

%% The operations map keeps terminal mutation and timing deterministic in the
%% Erlang contract tests; the production entry point always supplies this
%% module's real terminal operations.
query_background_with_ops(Stream, TimeoutMs, Ops) ->
    try
        query_background_with_ops_1(Stream, bounded_timeout(TimeoutMs), Ops)
    catch
        _:_ ->
            {error, nil}
    end.

query_background_with_ops_1(_Stream, 0, _Ops) ->
    {error, nil};
query_background_with_ops_1(Stream, TimeoutMs, Ops) ->
    case stream_target(Stream) of
        {ok, TtyKey, OutputDevice} ->
            Getopts = maps:get(getopts, Ops),
            case Getopts(standard_io) of
                Options when is_list(Options) ->
                    case option_enabled(Options, TtyKey) of
                        true ->
                            query_with_terminal_options(
                                OutputDevice,
                                TimeoutMs,
                                restorable_options(Options),
                                Ops
                            );
                        false ->
                            {error, nil}
                    end;
                _ ->
                    {error, nil}
            end;
        error ->
            {error, nil}
    end.

query_with_terminal_options(OutputDevice, TimeoutMs, OriginalOptions, Ops) ->
    Setopts = maps:get(setopts, Ops),
    try
        case Setopts(standard_io, [binary, {encoding, latin1}, {echo, false}]) of
            ok ->
                query_with_input(OutputDevice, TimeoutMs, Ops);
            _ ->
                {error, nil}
        end
    after
        restore_options(Setopts, OriginalOptions)
    end.

query_with_input(OutputDevice, TimeoutMs, Ops) ->
    PauseInput = maps:get(pause_input, Ops),
    ResumeInput = maps:get(resume_input, Ops),
    case PauseInput(TimeoutMs) of
        {ok, Reader} ->
            try
                query_with_paused_input(OutputDevice, TimeoutMs, Ops)
            after
                ensure_ok(ResumeInput(Reader, TimeoutMs), input_resume_failed)
            end;
        _ ->
            {error, nil}
    end.

query_with_paused_input(OutputDevice, TimeoutMs, Ops) ->
    OpenInput = maps:get(open_input, Ops),
    CloseInput = maps:get(close_input, Ops),
    case OpenInput() of
        {ok, Input} ->
            try
                Write = maps:get(write, Ops),
                case Write(OutputDevice, ?OSC_11_QUERY) of
                    ok ->
                        Now = maps:get(now, Ops),
                        Deadline = Now() + TimeoutMs,
                        read_response(Input, Deadline, Now, maps:get(read, Ops), <<>>, false);
                    _ ->
                        {error, nil}
                end
            after
                _ = CloseInput(Input)
            end;
        _ ->
            {error, nil}
    end.

read_response(Input, Deadline, Now, Read, Acc, PreviousWasEsc) ->
    Remaining = Deadline - Now(),
    case Remaining > 0 of
        false ->
            {error, nil};
        true ->
            case Read(Input, Remaining) of
                {ok, <<Byte>>} ->
                    Response = <<Acc/binary, Byte>>,
                    case Byte =:= 7 orelse (PreviousWasEsc andalso Byte =:= $\\) of
                        true ->
                            {ok, Response};
                        false ->
                            read_response(
                                Input,
                                Deadline,
                                Now,
                                Read,
                                Response,
                                Byte =:= 27
                            )
                    end;
                _ ->
                    {error, nil}
            end
    end.

bounded_timeout(TimeoutMs) when is_integer(TimeoutMs), TimeoutMs > 0 ->
    min(TimeoutMs, ?MAX_QUERY_TIMEOUT_MS);
bounded_timeout(_) ->
    0.

stream_target(stdin) -> {ok, stdin, standard_io};
stream_target(stdout) -> {ok, stdout, standard_io};
stream_target(stderr) -> {ok, stderr, standard_error};
stream_target(_) -> error.

option_enabled(Options, Key) ->
    proplists:get_value(Key, Options, false) =:= true.

restorable_options(Options) ->
    lists:filter(
        fun
            ({Key, _}) ->
                lists:member(Key, [expand_fun, echo, binary, encoding, log]);
            (_) ->
                false
        end,
        Options
    ).

restore_options(Setopts, OriginalOptions) ->
    ensure_ok(Setopts(standard_io, OriginalOptions), terminal_restore_failed).

ensure_ok(ok, _Failure) -> ok;
ensure_ok(_, Failure) -> error(Failure).

default_query_ops() ->
    #{
        getopts => fun io:getopts/1,
        setopts => fun io:setopts/2,
        pause_input => fun pause_tty_reader/1,
        resume_input => fun resume_tty_reader/2,
        open_input => fun open_tty_input/0,
        close_input => fun file:close/1,
        write => fun io:put_chars/2,
        read => fun read_tty_byte/2,
        now => fun() -> erlang:monotonic_time(millisecond) end
    }.

open_tty_input() ->
    case os:type() of
        {unix, _} ->
            file:open("/dev/tty", [read, raw, binary]);
        _ ->
            {error, enotsup}
    end.

pause_tty_reader(_TimeoutMs) ->
    case whereis(user_drv_reader) of
        Reader when is_pid(Reader) ->
            try erlang:suspend_process(Reader, [unless_suspending]) of
                true -> {ok, Reader};
                false -> {error, busy}
            catch
                _:_ -> {error, terminated}
            end;
        undefined ->
            {error, enotsup}
    end.

resume_tty_reader(Reader, _TimeoutMs) ->
    try erlang:resume_process(Reader) of
        true -> ok
    catch
        _:_ -> {error, terminated}
    end.

read_tty_byte(Input, TimeoutMs) ->
    ReplyAlias = erlang:alias(),
    {Reader, Monitor} =
        spawn_monitor(fun() ->
            ReplyAlias ! {ReplyAlias, file:read(Input, 1)}
        end),
    receive
        {ReplyAlias, Result} ->
            erlang:unalias(ReplyAlias),
            erlang:demonitor(Monitor, [flush]),
            normalize_byte_read(Result);
        {'DOWN', Monitor, process, Reader, _Reason} ->
            erlang:unalias(ReplyAlias),
            {error, nil}
    after TimeoutMs ->
        erlang:unalias(ReplyAlias),
        _ = file:close(Input),
        exit(Reader, kill),
        erlang:demonitor(Monitor, [flush]),
        {error, nil}
    end.

normalize_byte_read({ok, <<Byte>>}) ->
    {ok, <<Byte>>};
normalize_byte_read(_) ->
    {error, nil}.

%% Returns {ok, Value} | {error, nil} to match Gleam's Result(String, Nil).
get_env(Name) when is_binary(Name) ->
    case unicode:characters_to_list(Name) of
        EnvName when is_list(EnvName) ->
            case os:getenv(EnvName) of
                false -> {error, nil};
                Value -> env_value_to_result(Value)
            end;
        {error, _, _} ->
            {error, nil}
    end.

env_value_to_result(Value) ->
    case unicode:characters_to_binary(Value) of
        EnvValue when is_binary(EnvValue) -> {ok, EnvValue};
        {error, _, _} -> {error, nil}
    end.
