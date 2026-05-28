-module(echo_tool).
-behaviour(madoguchi_tool).

-export([name/0, description/0, input_schema/0, call/1]).

name() -> ~"echo".
description() -> ~"Echo back the message.".

input_schema() ->
    #{
        ~"type" => ~"object",
        ~"properties" => #{~"message" => #{~"type" => ~"string"}},
        ~"required" => [~"message"]
    }.

call(#{~"message" := M}) when is_binary(M) -> {ok, M};
call(_) -> {error, ~"missing message"}.
