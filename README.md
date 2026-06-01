# madoguchi

[![CI](https://github.com/Taure/madoguchi/actions/workflows/ci.yml/badge.svg)](https://github.com/Taure/madoguchi/actions/workflows/ci.yml)
[![OTP](https://img.shields.io/badge/OTP-29%2B-blue)](https://www.erlang.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](https://github.com/Taure/madoguchi/blob/main/LICENSE)

**窓口** ("service window") - an MCP server framework for the BEAM.

madoguchi turns any BEAM service into a [Model Context Protocol](https://modelcontextprotocol.io)
server, so agents - Claude Code, Cursor, or a [gakudan](https://github.com/Taure/gakudan)
agent - can call your tools over the wire. It speaks the Streamable HTTP
transport, JSON-RPC 2.0, protocol version `2025-06-18` (the same revision
gakudan's MCP client speaks, so the two interoperate end to end).

The protocol core is transport-agnostic: `madoguchi:dispatch/2` is a pure
function from a JSON-RPC message to a response, with no web dependency. A
bundled Cowboy handler serves it over HTTP, and the same dispatcher drops into
a Nova controller in ~12 lines (see the [guide](docs/getting-started.md)).

Because it is a BEAM library, tools can be authored in Erlang, Elixir, Gleam, or
LFE. Because MCP is a language-agnostic protocol, the servers you build are
callable by any MCP client in any language.

## Install

```erlang
%% rebar.config
{deps, [{madoguchi, {git, "https://github.com/Taure/madoguchi.git", {branch, "main"}}}]}.
```

## 60-second tour

Define a tool:

```erlang
-module(weather_tool).
-behaviour(madoguchi_tool).
-export([name/0, description/0, input_schema/0, call/1]).

name() -> ~"get_weather".
description() -> ~"Current weather for a city.".

input_schema() ->
    #{~"type" => ~"object",
      ~"properties" => #{~"city" => #{~"type" => ~"string"}},
      ~"required" => [~"city"]}.

call(#{~"city" := City}) ->
    {ok, <<"Sunny in ", City/binary>>}.
```

Serve it:

```erlang
Server = #{name => ~"weather", version => ~"1.0.0", tools => [weather_tool]},
{ok, _} = madoguchi:start_http(Server, #{port => 8080}).
```

Any MCP client can now `initialize`, `tools/list`, and `tools/call` against
`http://localhost:8080/mcp`.

## The tool behaviour

A tool is a module implementing four callbacks:

| Callback | Returns |
| --- | --- |
| `name/0` | the tool name (binary) |
| `description/0` | a human description (binary) |
| `input_schema/0` | a JSON Schema object (map) |
| `call/1` | `{ok, binary()}`, `{ok, [content()]}`, or `{error, binary()}` |

`content()` is `#{type => text, text => binary()}`. A `call/1` that returns
`{error, _}` or crashes becomes an MCP tool error (`isError => true`) on that
call - it never takes down the server.

## Mounting

- **Standalone:** `madoguchi:start_http/1,2` starts a Cowboy listener serving
  the MCP endpoint. It binds `127.0.0.1` by default (set `ip => {0, 0, 0, 0}` to
  expose it), validates the `Origin` header against `allowed_origins` (DNS-
  rebinding protection), and enforces `Accept` / `MCP-Protocol-Version`. See
  [SECURITY.md](SECURITY.md).
- **stdio (local launch):** `madoguchi_stdio:start/1` runs a newline-delimited
  JSON-RPC loop over stdin/stdout - the transport a client uses when it launches
  the server as a subprocess.
- **Inside your app:** mount `madoguchi_http_handler` as a route on your own Cowboy
  listener, or call `madoguchi:dispatch/2` from a Nova controller / Plug. The
  [getting-started guide](docs/getting-started.md) shows the Nova pattern.

## Roadmap

Deferred from this core: a `madoguchi_nova` bridge (config-driven controller +
plugin-based auth); a token-verification seam for authorization; and
input-schema validation.

## License

MIT.
