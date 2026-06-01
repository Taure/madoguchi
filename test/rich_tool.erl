-module(rich_tool).
-behaviour(madoguchi_tool).

-export([
    name/0,
    description/0,
    title/0,
    input_schema/0,
    output_schema/0,
    annotations/0,
    call/1
]).

name() -> ~"rich".
description() -> ~"A tool with annotations and structured output.".
title() -> ~"Rich Tool".

input_schema() ->
    #{~"type" => ~"object", ~"properties" => #{~"mode" => #{~"type" => ~"string"}}}.

output_schema() ->
    #{~"type" => ~"object", ~"properties" => #{~"score" => #{~"type" => ~"integer"}}}.

annotations() ->
    #{
        title => ~"Rich Tool",
        readOnlyHint => true,
        destructiveHint => false,
        idempotentHint => true,
        openWorldHint => false
    }.

call(#{~"mode" := ~"image"}) ->
    {ok, [madoguchi_tool:image(~"AAAA", ~"image/png")]};
call(#{~"mode" := ~"link"}) ->
    {ok, [madoguchi_tool:resource_link(~"mem://x", ~"x")]};
call(#{~"mode" := ~"structured"}) ->
    {ok, [madoguchi_tool:text(~"scored")], #{~"score" => 42}};
call(_) ->
    {ok, ~"plain"}.
