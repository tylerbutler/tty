-module(tty_ffi_contract_probe).
-export([invalid_env_name_returns_error/0, invalid_env_value_returns_error/0]).

invalid_env_name_returns_error() ->
    tty_ffi:get_env(<<255>>) =:= {error, nil}.

%% A lone surrogate codepoint is a valid integer but not encodable as UTF-8, so
%% unicode:characters_to_binary/1 returns {error, _, _}. The OS refuses to store
%% such a value via os:putenv, so this branch can only be exercised by calling
%% the helper directly.
invalid_env_value_returns_error() ->
    tty_ffi:env_value_to_result([16#D800]) =:= {error, nil}.
