-module(tty_ffi_contract_probe).
-export([
    invalid_env_name_returns_error/0,
    invalid_env_value_returns_error/0,
    osc_non_tty_has_no_side_effects/0,
    osc_success_restores_and_stops_at_terminator/0,
    osc_timeout_is_bounded_and_restores/0,
    osc_failures_and_exception_restore/0,
    osc_whole_call_timeout_is_bounded/0,
    osc_real_tty_reaches_io_path/0
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
    WriteErrorRestored andalso ReadErrorRestored andalso ExceptionRestored.

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
            {write, fun(_Device, _Data) -> timer:sleep(250), ok end},
            {close_input, fun(_Input, _Timeout) -> timer:sleep(250), ok end}
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

osc_real_tty_reaches_io_path() ->
    case tty_ffi:stdout_is_tty() of
        false ->
            true;
        true ->
            StartedAt = erlang:monotonic_time(millisecond),
            Result = tty_ffi:query_background(stdout, 100),
            Elapsed = erlang:monotonic_time(millisecond) - StartedAt,
            ReachedRead =
                case Result of
                    {ok, Response} -> is_binary(Response);
                    {error, nil} -> Elapsed >= 50
                end,
            ReachedRead andalso Elapsed =< 200
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
        lists:any(
            fun
                ({resume_input, fake_reader, _}) -> true;
                (_) -> false
            end,
            Events
        ) andalso
        lists:last(Events) =:= {setopts, standard_io, OriginalOptions}.

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
