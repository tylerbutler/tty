-module(tty_ffi_contract_probe).
-export([
    invalid_env_name_returns_error/0,
    invalid_env_value_returns_error/0,
    osc_non_tty_has_no_side_effects/0,
    osc_success_restores_and_stops_at_terminator/0,
    osc_timeout_is_bounded_and_restores/0,
    osc_failures_and_exception_restore/0
]).

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
    put(probe_read_result, {error, nil}),
    Result = tty_ffi:query_background_with_ops(
        stdout,
        1000,
        fake_ops(terminal_options(), <<>>)
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
    WriteErrorRestored andalso ReadErrorRestored andalso ExceptionRestored.

failure_restores(Key, Value) ->
    reset_probe(),
    put(Key, Value),
    Result = tty_ffi:query_background_with_ops(
        stdout,
        100,
        fake_ops(terminal_options(), <<"ignored">>)
    ),
    Result =:= {error, nil} andalso restored(events()).

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
    put(probe_input, Input),
    #{
        getopts => fun(Device) ->
            record({getopts, Device}),
            Options
        end,
        setopts => fun(Device, NewOptions) ->
            record({setopts, Device, NewOptions}),
            ok
        end,
        pause_input => fun(Timeout) ->
            record({pause_input, Timeout}),
            {ok, fake_reader}
        end,
        resume_input => fun(Reader, Timeout) ->
            record({resume_input, Reader, Timeout}),
            ok
        end,
        open_input => fun() ->
            record(open_input),
            {ok, fake_input}
        end,
        close_input => fun(InputHandle) ->
            record({close_input, InputHandle}),
            ok
        end,
        write => fun(Device, Data) ->
            record({write, Device, Data}),
            case get(write_result) of
                undefined -> ok;
                WriteResult -> WriteResult
            end
        end,
        read => fun(_InputHandle, Timeout) ->
            record({read, Timeout}),
            fake_read()
        end,
        now => fun() -> 0 end
    }.

fake_read() ->
    case get(probe_read_result) of
        raise ->
            error(injected_read_failure);
        undefined ->
            case get(probe_input) of
                <<Byte, Rest/binary>> ->
                    put(probe_input, Rest),
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
        lists:any(
            fun
                ({resume_input, fake_reader, _}) -> true;
                (_) -> false
            end,
            Events
        ) andalso
        lists:last(Events) =:= {setopts, standard_io, OriginalOptions}.

remaining_input() ->
    get(probe_input).

reset_probe() ->
    erase(probe_events),
    erase(probe_input),
    erase(probe_read_result),
    erase(write_result),
    ok.

record(Event) ->
    Recorded =
        case get(probe_events) of
            undefined -> [];
            Existing -> Existing
        end,
    put(probe_events, [Event | Recorded]),
    ok.

events() ->
    lists:reverse(
        case get(probe_events) of
            undefined -> [];
            Recorded -> Recorded
        end
    ).
