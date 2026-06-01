-module(greeting_prompt).
-behaviour(madoguchi_prompt).

-export([name/0, description/0, arguments/0, get/1]).

name() -> ~"greeting".
description() -> ~"Greet someone by name.".

arguments() ->
    [#{name => ~"who", description => ~"Who to greet.", required => true}].

get(#{~"who" := Who}) when is_binary(Who) ->
    {ok, ~"A greeting", [madoguchi_prompt:user(<<"Say hi to ", Who/binary>>)]};
get(#{~"crash" := _}) ->
    error(boom);
get(_) ->
    {error, ~"missing who"}.
