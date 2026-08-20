-module(tty_ffi_contract_probe).
-export([
    invalid_env_name_returns_error/0,
    invalid_env_value_returns_error/0,
    osc_non_tty_has_no_side_effects/0,
    osc_success_restores_and_stops_at_terminator/0,
    osc_timeout_is_bounded_and_restores/0,
    osc_failures_and_exception_restore/0,
    osc_whole_call_timeout_is_bounded/0,
    osc_real_tty_handles_bare_reply/0,
    pty_bare_reply_preserves_mode/0
]).

-define(OSC_11_QUERY, <<27, "]11;?", 7>>).
-define(OSC_11_RESPONSE, <<27, "]11;rgb:ffff/0000/0000", 7>>).

invalid_env_name_returns_error() ->
    tty_ffi:get_env(<<255>>) =:= {error, nil}.

%% A lone surrogate codepoint is a valid integer but not encodable as UTF-8, so
%% unicode:characters_to_binary/1 returns {error, _, _}. The OS refuses to store
%% such a value via os:putenv, so this branch can only be exercised by calling
%% the helper directly.
invalid_env_value_returns_error() ->
    tty_ffi:env_value_to_result([16#D800]) =:= {error, nil}.

osc_non_tty_has_no_side_effects() ->
    reset_probe(),
    Ops = fake_ops([{stdout, false}], []),
    Result = tty_ffi:query_background_with_ops(stdout, 100, Ops),
    Result =:= {error, nil} andalso events() =:= [{getopts, standard_io}].

osc_success_restores_and_stops_at_terminator() ->
    BelResponse = <<27, "]11;rgb:ff/00/00", 7>>,
    reset_probe(),
    BelResult = tty_ffi:query_background_with_ops(
        stdout,
        100,
        fake_ops(terminal_options(), <<BelResponse/binary, "unread">>)
    ),
    BelState = {events(), remaining_input()},

    StResponse = <<27, "]11;rgb:0000/ffff/0000", 27, $\\>>,
    reset_probe(),
    StResult = tty_ffi:query_background_with_ops(
        stderr,
        100,
        fake_ops(terminal_options(), <<StResponse/binary, "unread">>)
    ),
    StState = {events(), remaining_input()},

    BelResult =:= {ok, BelResponse} andalso
        restored_after_query(BelState, standard_io) andalso
        StResult =:= {ok, StResponse} andalso
        restored_after_query(StState, standard_error).

osc_timeout_is_bounded_and_restores() ->
    reset_probe(),
    Ops = fake_ops(terminal_options(), <<>>),
    set_probe(probe_read_result, {error, nil}),
    Result = tty_ffi:query_background_with_ops(
        stdout,
        1000,
        Ops
    ),
    ReadTimeouts = [Timeout || {read, Timeout} <- events()],
    Result =:= {error, nil} andalso
        ReadTimeouts =/= [] andalso
        lists:all(fun(Timeout) -> Timeout =< 100 end, ReadTimeouts) andalso
        restored(events()).

osc_failures_and_exception_restore() ->
    WriteErrorRestored = failure_restores(write_result, {error, closed}),
    ReadErrorRestored = failure_restores(probe_read_result, {error, closed}),
    ExceptionRestored = failure_restores(probe_read_result, raise),
    RawModeErrorRestored = raw_mode_failure_restores(),
    WriteErrorRestored andalso
        ReadErrorRestored andalso
        ExceptionRestored andalso
        RawModeErrorRestored.

raw_mode_failure_restores() ->
    reset_probe(),
    Ops = fake_ops(terminal_options(), <<"ignored">>),
    set_probe(set_terminal_raw_result, {error, denied}),
    Result = tty_ffi:query_background_with_ops(stdout, 100, Ops),
    Result =:= {error, nil} andalso
        events() =:=
            [
                {getopts, standard_io},
                get_terminal_mode,
                {set_terminal_raw, saved_mode},
                {restore_terminal_mode, saved_mode}
            ].

failure_restores(Key, Value) ->
    reset_probe(),
    Ops = fake_ops(terminal_options(), <<"ignored">>),
    set_probe(Key, Value),
    Result = tty_ffi:query_background_with_ops(
        stdout,
        100,
        Ops
    ),
    Result =:= {error, nil} andalso restored(events()).

osc_whole_call_timeout_is_bounded() ->
    lists:all(
        fun blocked_op_is_bounded/1,
        [
            {getopts, fun(_Device) -> timer:sleep(250), terminal_options() end},
            {get_terminal_mode, fun(_QueryProcess) ->
                timer:sleep(250), {ok, saved_mode}
            end},
            {write, fun(_Device, _Data) -> timer:sleep(250), ok end},
            {close_input, fun(_Input, _Timeout) -> timer:sleep(250), ok end},
            {restore_terminal_mode, fun(_Mode) -> timer:sleep(250), ok end}
        ]
    ).

blocked_op_is_bounded({Key, BlockingFun}) ->
    reset_probe(),
    Response = <<27, "]11;rgb:ff/00/00", 7>>,
    Ops = maps:put(Key, BlockingFun, fake_ops(terminal_options(), Response)),
    StartedAt = erlang:monotonic_time(millisecond),
    Result = tty_ffi:query_background_with_ops(stdout, 100, Ops),
    Elapsed = erlang:monotonic_time(millisecond) - StartedAt,
    Result =:= {error, nil} andalso Elapsed =< 200.

osc_real_tty_handles_bare_reply() ->
    case {os:type(), os:find_executable("script"), os:find_executable("erl")} of
        {{unix, Platform}, Script, Erl} when is_list(Script), is_list(Erl) ->
            Ebin = filename:dirname(code:which(tty_ffi)),
            ProbeEbin = filename:dirname(code:which(?MODULE)),
            pty_query_succeeds(noshell, Platform, Script, Erl, Ebin, ProbeEbin) andalso
                pty_query_succeeds(interactive, Platform, Script, Erl, Ebin, ProbeEbin);
        {{unix, _Platform}, _Script, _Erl} ->
            false;
        _ ->
            true
    end.

pty_query_succeeds(Mode, Platform, Script, Erl, Ebin, ProbeEbin) ->
    Eval = pty_eval(),
    ErlArgs =
        case Mode of
            noshell -> ["-noshell", "-pa", Ebin, ProbeEbin, "-eval", Eval];
            interactive -> ["-pa", Ebin, ProbeEbin]
        end,
    ScriptArgs = script_args(Platform, Erl, ErlArgs),
    Port = open_port(
        {spawn_executable, Script},
        [binary, exit_status, use_stdio, stderr_to_stdout, {args, ScriptArgs}]
    ),
    try
        Started =
            case Mode of
                noshell ->
                    true;
                interactive ->
                    case receive_until(Port, <<"1>">>, 5000, <<>>) of
                        {ok, _Output} ->
                            erlang:port_command(Port, [Eval, "\n"]);
                        error ->
                            false
                    end
            end,
        Started =:= true andalso complete_pty_query(Port)
    after
        catch erlang:port_close(Port)
    end.

complete_pty_query(Port) ->
    case receive_until(Port, ?OSC_11_QUERY, 5000, <<>>) of
        {ok, _Output} ->
            true = erlang:port_command(Port, ?OSC_11_RESPONSE),
            case receive_until(Port, <<"PTY_RESULT=true">>, 5000, <<>>) of
                {ok, _ResultOutput} -> wait_for_exit(Port, 5000);
                error -> false
            end;
        error ->
            false
    end.

pty_eval() ->
    "Result = tty_ffi_contract_probe:pty_bare_reply_preserves_mode(), "
    "io:format(\"PTY_RESULT=~p~n\",[Result]), halt().".

pty_bare_reply_preserves_mode() ->
    TtyName = string:trim(
        os:cmd("ps -o tty= -p " ++ os:getpid() ++ " 2>/dev/null")
    ),
    case valid_pty_name(TtyName) of
        true ->
            Device = filename:join("/dev", TtyName),
            Before = os:cmd("stty -g < " ++ Device ++ " 2>/dev/null"),
            StartedAt = erlang:monotonic_time(millisecond),
            Result = tty_ffi:query_background(stdout, 100),
            Elapsed = erlang:monotonic_time(millisecond) - StartedAt,
            After = os:cmd("stty -g < " ++ Device ++ " 2>/dev/null"),
            Result =:= {ok, ?OSC_11_RESPONSE} andalso
                Elapsed =< 200 andalso
                Before =/= [] andalso
                After =:= Before;
        false ->
            false
    end.

valid_pty_name([]) ->
    false;
valid_pty_name(Name) ->
    Segments = string:split(Name, "/", all),
    lists:all(
        fun(Segment) ->
            Segment =/= [] andalso
                Segment =/= "." andalso
                Segment =/= ".." andalso
                lists:all(
                    fun(Char) ->
                        (Char >= $a andalso Char =< $z) orelse
                            (Char >= $A andalso Char =< $Z) orelse
                            (Char >= $0 andalso Char =< $9) orelse
                            lists:member(Char, "_-")
                    end,
                    Segment
                )
        end,
        Segments
    ).

script_args(darwin, Erl, ErlArgs) ->
    ["-q", "/dev/null", Erl | ErlArgs];
script_args(_Platform, Erl, ErlArgs) ->
    Command = string:join([shell_quote(Arg) || Arg <- [Erl | ErlArgs]], " "),
    ["-q", "-c", Command, "/dev/null"].

shell_quote(Arg) ->
    "'" ++ lists:flatten(string:replace(Arg, "'", "'\\''", all)) ++ "'".

receive_until(Port, Marker, TimeoutMs, Acc) ->
    Deadline = erlang:monotonic_time(millisecond) + TimeoutMs,
    receive_until_deadline(Port, Marker, Deadline, Acc).

receive_until_deadline(Port, Marker, Deadline, Acc) ->
    case binary:match(Acc, Marker) of
        {_, _} ->
            {ok, Acc};
        nomatch ->
            Remaining = max(0, Deadline - erlang:monotonic_time(millisecond)),
            receive
                {Port, {data, Data}} ->
                    receive_until_deadline(Port, Marker, Deadline, <<Acc/binary, Data/binary>>);
                {Port, {exit_status, _Status}} ->
                    error
            after Remaining ->
                error
            end
    end.

wait_for_exit(Port, TimeoutMs) ->
    receive
        {Port, {exit_status, 0}} -> true;
        {Port, {exit_status, _Status}} -> false
    after TimeoutMs ->
        false
    end.

terminal_options() ->
    [
        {echo, true},
        {binary, false},
        {encoding, unicode},
        {log, none},
        {terminal, true},
        {stdin, true},
        {stdout, true},
        {stderr, true}
    ].

fake_ops(Options, Input) ->
    Table = ets:new(?MODULE, [ordered_set, public]),
    true = ets:insert(Table, [{sequence, 0}, {probe_input, Input}]),
    put(probe_table, Table),
    #{
        getopts => fun(Device) ->
            record(Table, {getopts, Device}),
            Options
        end,
        setopts => fun(Device, NewOptions) ->
            record(Table, {setopts, Device, NewOptions}),
            ok
        end,
        get_terminal_mode => fun(_QueryProcess) ->
            record(Table, get_terminal_mode),
            {ok, saved_mode}
        end,
        set_terminal_raw => fun(Mode) ->
            record(Table, {set_terminal_raw, Mode}),
            case probe_value(Table, set_terminal_raw_result) of
                undefined -> ok;
                RawResult -> RawResult
            end
        end,
        restore_terminal_mode => fun(Mode) ->
            record(Table, {restore_terminal_mode, Mode}),
            ok
        end,
        pause_input => fun(Timeout) ->
            record(Table, {pause_input, Timeout}),
            {ok, fake_reader}
        end,
        resume_input => fun(Reader, Timeout) ->
            record(Table, {resume_input, Reader, Timeout}),
            ok
        end,
        open_input => fun() ->
            record(Table, open_input),
            {ok, fake_input}
        end,
        close_input => fun(InputHandle, _Timeout) ->
            record(Table, {close_input, InputHandle}),
            ok
        end,
        write => fun(Device, Data) ->
            record(Table, {write, Device, Data}),
            case probe_value(Table, write_result) of
                undefined -> ok;
                WriteResult -> WriteResult
            end
        end,
        read => fun(_InputHandle, Timeout) ->
            record(Table, {read, Timeout}),
            fake_read(Table)
        end
    }.

fake_read(Table) ->
    case probe_value(Table, probe_read_result) of
        raise ->
            error(injected_read_failure);
        undefined ->
            case probe_value(Table, probe_input) of
                <<Byte, Rest/binary>> ->
                    true = ets:insert(Table, {probe_input, Rest}),
                    {ok, <<Byte>>};
                <<>> ->
                    {error, nil}
            end;
        ReadResult ->
            ReadResult
    end.

restored_after_query({Events, Remaining}, OutputDevice) ->
    Remaining =:= <<"unread">> andalso
        lists:member({write, OutputDevice, <<27, "]11;?", 7>>}, Events) andalso
        restored(Events).

restored(Events) ->
    RawOptions = [binary, {encoding, latin1}, {echo, false}],
    OriginalOptions = [
        {echo, true},
        {binary, false},
        {encoding, unicode},
        {log, none}
    ],
    lists:member({setopts, standard_io, RawOptions}, Events) andalso
        lists:member(get_terminal_mode, Events) andalso
        lists:member({set_terminal_raw, saved_mode}, Events) andalso
        lists:any(
            fun
                ({resume_input, fake_reader, _}) -> true;
                (_) -> false
            end,
            Events
        ) andalso
        lists:member({setopts, standard_io, OriginalOptions}, Events) andalso
        lists:last(Events) =:= {restore_terminal_mode, saved_mode}.

remaining_input() ->
    probe_value(probe_table(), probe_input).

reset_probe() ->
    case erase(probe_table) of
        undefined -> ok;
        Table -> ets:delete(Table)
    end,
    ok.

set_probe(Key, Value) ->
    true = ets:insert(probe_table(), {Key, Value}),
    ok.

record(Table, Event) ->
    Sequence = ets:update_counter(Table, sequence, 1),
    true = ets:insert(Table, {{event, Sequence}, Event}),
    ok.

events() ->
    [Event || {{event, _Sequence}, Event} <- ets:tab2list(probe_table())].

probe_table() ->
    get(probe_table).

probe_value(Table, Key) ->
    case ets:lookup(Table, Key) of
        [{Key, Value}] -> Value;
        [] -> undefined
    end.
