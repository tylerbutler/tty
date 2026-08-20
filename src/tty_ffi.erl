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
-define(CLEANUP_BUDGET_MS, 10).

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
        Timeout = bounded_timeout(TimeoutMs),
        Deadline = now_ms() + Timeout,
        WorkDeadline = max(now_ms(), Deadline - ?CLEANUP_BUDGET_MS),
        query_background_with_ops_1(Stream, Timeout, WorkDeadline, Deadline, Ops)
    catch
        _:_ ->
            {error, nil}
    end.

query_background_with_ops_1(_Stream, 0, _WorkDeadline, _Deadline, _Ops) ->
    {error, nil};
query_background_with_ops_1(Stream, _TimeoutMs, WorkDeadline, Deadline, Ops) ->
    case stream_target(Stream) of
        {ok, TtyKey, OutputDevice} ->
            case run_op(getopts, [standard_io], WorkDeadline, Ops) of
                {ok, Options} when is_list(Options) ->
                    case option_enabled(Options, TtyKey) of
                        true ->
                            query_with_terminal_options(
                                OutputDevice,
                                restorable_options(Options),
                                WorkDeadline,
                                Deadline,
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

query_with_terminal_options(OutputDevice, OriginalOptions, WorkDeadline, Deadline, Ops) ->
    try
        case run_op(
            setopts,
            [standard_io, [binary, {encoding, latin1}, {echo, false}]],
            WorkDeadline,
            Ops
        ) of
            {ok, ok} ->
                query_with_input(OutputDevice, WorkDeadline, Deadline, Ops);
            _ ->
                {error, nil}
        end
    after
        restore_options(OriginalOptions, Deadline, Ops)
    end.

query_with_input(OutputDevice, WorkDeadline, Deadline, Ops) ->
    case run_op(pause_input, [remaining_ms(WorkDeadline)], WorkDeadline, Ops) of
        {ok, {ok, Reader}} ->
            try
                query_with_paused_input(OutputDevice, WorkDeadline, Deadline, Ops)
            after
                ensure_op_ok(
                    resume_input,
                    [Reader, remaining_ms(Deadline)],
                    Deadline,
                    Ops,
                    input_resume_failed
                )
            end;
        _ ->
            {error, nil}
    end.

query_with_paused_input(OutputDevice, WorkDeadline, Deadline, Ops) ->
    case run_op(open_input, [], WorkDeadline, Ops) of
        {ok, {ok, Input}} ->
            try
                case run_op(write, [OutputDevice, ?OSC_11_QUERY], WorkDeadline, Ops) of
                    {ok, ok} ->
                        read_response(Input, WorkDeadline, Ops, <<>>, false);
                    _ ->
                        {error, nil}
                end
            after
                ensure_op_ok(
                    close_input,
                    [Input, remaining_ms(Deadline)],
                    Deadline,
                    Ops,
                    input_close_failed
                )
            end;
        _ ->
            {error, nil}
    end.

read_response(Input, Deadline, Ops, Acc, PreviousWasEsc) ->
    Remaining = remaining_ms(Deadline),
    case Remaining > 0 of
        false ->
            {error, nil};
        true ->
            case run_op(read, [Input, Remaining], Deadline, Ops) of
                {ok, {ok, <<Byte>>}} ->
                    Response = <<Acc/binary, Byte>>,
                    case Byte =:= 7 orelse (PreviousWasEsc andalso Byte =:= $\\) of
                        true ->
                            {ok, Response};
                        false ->
                            read_response(
                                Input,
                                Deadline,
                                Ops,
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

restore_options(OriginalOptions, Deadline, Ops) ->
    ensure_op_ok(
        setopts,
        [standard_io, OriginalOptions],
        Deadline,
        Ops,
        terminal_restore_failed
    ).

ensure_op_ok(Key, Args, Deadline, Ops, Failure) ->
    case run_op(Key, Args, Deadline, Ops) of
        {ok, ok} -> ok;
        _ -> error(Failure)
    end.

run_op(Key, Args, Deadline, Ops) ->
    case remaining_ms(Deadline) of
        0 ->
            {error, timeout};
        Remaining ->
            Fun = maps:get(Key, Ops),
            ReplyAlias = erlang:alias(),
            {Worker, Monitor} =
                spawn_monitor(fun() ->
                    Result =
                        try
                            {ok, erlang:apply(Fun, Args)}
                        catch
                            _:_ -> {error, operation_failed}
                        end,
                    ReplyAlias ! {ReplyAlias, Result}
                end),
            receive
                {ReplyAlias, Result} ->
                    erlang:unalias(ReplyAlias),
                    erlang:demonitor(Monitor, [flush]),
                    Result;
                {'DOWN', Monitor, process, Worker, _Reason} ->
                    erlang:unalias(ReplyAlias),
                    {error, operation_failed}
            after Remaining ->
                erlang:unalias(ReplyAlias),
                exit(Worker, kill),
                erlang:demonitor(Monitor, [flush]),
                receive
                    {'DOWN', Monitor, process, Worker, _Reason} -> ok
                after 0 ->
                    ok
                end,
                {error, timeout}
            end
    end.

remaining_ms(Deadline) ->
    max(0, Deadline - now_ms()).

now_ms() ->
    erlang:monotonic_time(millisecond).

default_query_ops() ->
    #{
        getopts => fun io:getopts/1,
        setopts => fun io:setopts/2,
        pause_input => fun pause_tty_reader/1,
        resume_input => fun resume_tty_reader/2,
        open_input => fun open_tty_input/0,
        close_input => fun close_tty_input/2,
        write => fun io:put_chars/2,
        read => fun read_tty_byte/2
    }.

open_tty_input() ->
    case os:type() of
        {unix, _} ->
            Parent = self(),
            Ref = make_ref(),
            _Owner = spawn_link(fun() ->
                case file:open("/dev/tty", [read, raw, binary]) of
                    {ok, Input} ->
                        Parent ! {Ref, {ok, self()}},
                        tty_input_loop(Input);
                    Error ->
                        Parent ! {Ref, Error}
                end
            end),
            receive
                {Ref, Result} -> Result
            end;
        _ ->
            {error, enotsup}
    end.

tty_input_loop(Input) ->
    receive
        {read, ReplyAlias} ->
            ReplyAlias ! {ReplyAlias, file:read(Input, 1)},
            tty_input_loop(Input);
        {close, ReplyAlias} ->
            ReplyAlias ! {ReplyAlias, file:close(Input)}
    end.

close_tty_input(Input, TimeoutMs) ->
    call_tty_input(Input, close, max(0, TimeoutMs - 1)).

pause_tty_reader(TimeoutMs) ->
    case whereis(user_drv_reader) of
        Reader when is_pid(Reader) ->
            case call_tty_reader(Reader, disable, TimeoutMs) of
                ok -> {ok, Reader};
                Error -> Error
            end;
        undefined ->
            {ok, none}
    end.

resume_tty_reader(none, _TimeoutMs) ->
    ok;
resume_tty_reader(Reader, TimeoutMs) ->
    call_tty_reader(Reader, enable, TimeoutMs).

call_tty_reader(Reader, Request, TimeoutMs) ->
    ReplyAlias = erlang:monitor(process, Reader, [{alias, reply_demonitor}]),
    Reader ! {ReplyAlias, Request},
    receive
        {ReplyAlias, Reply} ->
            Reply;
        {'DOWN', ReplyAlias, process, Reader, _Reason} ->
            {error, terminated}
    after TimeoutMs ->
        erlang:demonitor(ReplyAlias, [flush]),
        RecoveryAlias = erlang:alias(),
        Reader ! {RecoveryAlias, enable},
        erlang:unalias(RecoveryAlias),
        {error, timeout}
    end.

read_tty_byte(Input, TimeoutMs) ->
    case call_tty_input(Input, read, max(0, TimeoutMs - 1)) of
        {ok, <<Byte>>} -> {ok, <<Byte>>};
        _ -> {error, nil}
    end.

call_tty_input(Input, Request, TimeoutMs) ->
    ReplyAlias = erlang:monitor(process, Input, [{alias, reply_demonitor}]),
    Input ! {Request, ReplyAlias},
    receive
        {ReplyAlias, Result} ->
            Result;
        {'DOWN', ReplyAlias, process, Input, _Reason} ->
            {error, closed}
    after TimeoutMs ->
        erlang:demonitor(ReplyAlias, [flush]),
        exit(Input, kill),
        {error, timeout}
    end.

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
