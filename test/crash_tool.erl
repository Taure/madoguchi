-module(crash_tool).
-behaviour(madoguchi_tool).

-export([name/0, description/0, input_schema/0, call/1]).

name() -> ~"crash".
description() -> ~"Always crashes.".
input_schema() -> #{~"type" => ~"object"}.

call(_Arguments) -> error(boom).
