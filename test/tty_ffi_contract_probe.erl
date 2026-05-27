-module(tty_ffi_contract_probe).
-export([invalid_env_name_returns_error/0]).

invalid_env_name_returns_error() ->
    tty_ffi:get_env(<<255>>) =:= {error, nil}.
