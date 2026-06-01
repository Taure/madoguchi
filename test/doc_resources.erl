-module(doc_resources).
-behaviour(madoguchi_resource).

-export([list/0, templates/0, read/1]).

list() ->
    [
        #{
            uri => ~"mem://greeting",
            name => ~"greeting",
            description => ~"A friendly greeting.",
            mimeType => ~"text/plain"
        }
    ].

templates() ->
    [
        #{
            uriTemplate => ~"mem://doc/{id}",
            name => ~"doc",
            description => ~"A document by id."
        }
    ].

read(~"mem://greeting") ->
    {ok, [madoguchi_resource:text(~"mem://greeting", ~"hello")]};
read(~"mem://doc/1") ->
    {ok, [madoguchi_resource:text(~"mem://doc/1", ~"doc one")]};
read(~"mem://boom") ->
    error(kaboom);
read(_Uri) ->
    {error, not_found}.
