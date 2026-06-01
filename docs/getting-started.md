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

## Serving it, option 2: stdio (local launch)

Most local MCP servers are launched as a subprocess and speak newline-delimited
JSON-RPC over stdin/stdout. Run that loop with `madoguchi_stdio:start/1`:

```erlang
%% server entry point (e.g. an escript main/1)
main(_) ->
    Server = #{name => ~"calculator", version => ~"1.0.0", tools => [add_tool]},
    madoguchi_stdio:start(Server).
```

Point a client's `command` at that escript. One JSON-RPC document per line in,
one response line out per request; notifications produce no output. Keep stdout
clean - it carries only MCP messages, so send any logging to stderr.

## Serving it, option 3: inside a Nova app

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

## Resources

Beyond tools, a server can expose readable context as *resources*. A resource
provider is a module implementing `madoguchi_resource`:

```erlang
-module(doc_resources).
-behaviour(madoguchi_resource).
-export([list/0, templates/0, read/1]).

list() ->
    [#{uri => ~"mem://greeting", name => ~"greeting", mimeType => ~"text/plain"}].

templates() ->
    [#{uriTemplate => ~"mem://doc/{id}", name => ~"doc"}].

read(~"mem://greeting") -> {ok, [madoguchi_resource:text(~"mem://greeting", ~"hello")]};
read(_Uri) -> {error, not_found}.
```

List providers in the server definition under `resources`; the server then
answers `resources/list`, `resources/templates/list`, and `resources/read`, and
advertises the `resources` capability:

```erlang
Server = #{name => ~"calculator", version => ~"1.0.0",
           tools => [add_tool], resources => [doc_resources]}.
```

`templates/0` is optional. `read/1` returns `{ok, [contents()]}`,
`{error, not_found}`, or `{error, binary()}`; a crash is isolated to that read.

## Prompts

A server can also expose *prompts* - named, parameterised message templates a
client surfaces as slash commands. A prompt is a module implementing
`madoguchi_prompt`:

```erlang
-module(greeting_prompt).
-behaviour(madoguchi_prompt).
-export([name/0, description/0, arguments/0, get/1]).

name() -> ~"greeting".
description() -> ~"Greet someone by name.".

arguments() ->
    [#{name => ~"who", description => ~"Who to greet.", required => true}].

get(#{~"who" := Who}) ->
    {ok, [madoguchi_prompt:user(<<"Say hi to ", Who/binary>>)]}.
```

List prompts under `prompts`; the server answers `prompts/list` and
`prompts/get` and advertises the `prompts` capability:

```erlang
Server = #{name => ~"calculator", version => ~"1.0.0",
           tools => [add_tool], prompts => [greeting_prompt]}.
```

`arguments/0` is optional. `get/1` returns `{ok, [message()]}`,
`{ok, Description, [message()]}`, or `{error, binary()}`; build messages with
`madoguchi_prompt:user/1`, `assistant/1`, or `message/2`.

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
