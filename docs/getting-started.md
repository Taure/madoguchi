# Getting started

madoguchi exposes your BEAM service as an MCP server. This guide builds one from
a tool, then shows the two ways to serve it.

## A tool

A tool is a module implementing `madoguchi_tool`:

```erlang
-module(add_tool).
-behaviour(madoguchi_tool).
-export([name/0, description/0, input_schema/0, call/1]).

name() -> ~"add".
description() -> ~"Add two integers.".

input_schema() ->
    #{~"type" => ~"object",
      ~"properties" => #{~"a" => #{~"type" => ~"integer"},
                         ~"b" => #{~"type" => ~"integer"}},
      ~"required" => [~"a", ~"b"]}.

call(#{~"a" := A, ~"b" := B}) ->
    {ok, integer_to_binary(A + B)}.
```

`call/1` may return `{ok, binary()}` (one text block), `{ok, [content()]}`, or
`{error, binary()}`. An error or a crash becomes an MCP tool error on that call;
the server stays up.

## A server definition

```erlang
Server = #{name => ~"calculator", version => ~"1.0.0", tools => [add_tool]}.
```

## Serving it, option 1: standalone

```erlang
{ok, _} = madoguchi:start_http(Server, #{port => 8080}).
```

A Cowboy listener now answers MCP at `http://localhost:8080/mcp`. Point any MCP
client at it - Claude Code, Cursor, or gakudan's client.

The listener binds `127.0.0.1` by default so it is reachable only from the local
machine; pass `ip => {0, 0, 0, 0}` to expose it on all interfaces. It also
validates the `Origin` header (default `same_host`, configurable via
`allowed_origins`) and enforces `Accept` and `MCP-Protocol-Version`. See
[SECURITY.md](../SECURITY.md).

## Serving it, option 2: inside a Nova app

madoguchi's core is transport-agnostic: `madoguchi:dispatch/2` is a pure
function. In a Nova app you call it from a small controller - no Cowboy handler,
no new dependency (your Nova app already runs on Cowboy).

A controller:

```erlang
-module(myapp_mcp_controller).
-export([handle/1]).

server() ->
    #{name => ~"myapp", version => ~"1.0.0", tools => [add_tool]}.

handle(Req0) ->
    {ok, Body, _Req1} = cowboy_req:read_body(Req0),
    case madoguchi:dispatch(Body, server()) of
        {reply, Response} -> {json, 200, #{}, Response};
        noreply -> {status, 202}
    end.
```

A route in your `nova_router`:

```erlang
{"/mcp", fun myapp_mcp_controller:handle/1, #{methods => [post]}}
```

Put that route in a `security => fun ...:check/1` group and Nova's auth +
plugin pipeline applies to your MCP endpoint like any other route. (A
`madoguchi_nova` companion that packages this controller, a route helper, and
plugin-based auth is on the roadmap.)

## Calling it

Any MCP client speaks the same protocol. A raw `tools/call` over HTTP:

```bash
curl -s http://localhost:8080/mcp \
  -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call",
       "params":{"name":"add","arguments":{"a":2,"b":3}}}'
# => {"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"5"}],"isError":false}}
```

## Testing without a socket

Because `dispatch/2` is pure, you test the protocol by feeding it messages - no
listener required:

```erlang
{reply, #{result := #{tools := Tools}}} =
    madoguchi:dispatch(#{~"jsonrpc" => ~"2.0", ~"id" => 1, ~"method" => ~"tools/list"}, Server).
```
