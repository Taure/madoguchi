# 1. MCP server core

Date: 2026-05-28

## Status

Accepted (v0.1).

## Context

gakudan can *call* MCP servers (`gakudan_mcp_client`, Streamable HTTP, protocol
`2025-06-18`). The other half is missing: a way to *expose* a BEAM service as an
MCP server so agents - Claude Code, Cursor, a gakudan agent - can call its
tools. No good MCP server framework exists outside the Python/TypeScript SDKs,
and none on the BEAM.

The design has to satisfy three forces:

1. **Mountable anywhere.** Consumers run Nova, raw Cowboy, or no web app at all.
   The library must not impose a web framework. It also must be usable from any
   BEAM language (Erlang, Elixir, Gleam, LFE), since the host could be any of
   them.
2. **Spec-faithful and interoperable.** It must speak the same protocol revision
   as gakudan's client (`2025-06-18`) so the two interoperate, and so any
   third-party MCP client (Python SDK, TS SDK, Claude Code) works unmodified.
3. **Testable without sockets.** The protocol logic must be assertable
   deterministically, the same discipline gakudan and saiten apply via stubs.

## Decision

A transport-agnostic protocol core plus a thin Cowboy transport. The core
depends on nothing but OTP; the transport adds Cowboy.

### `madoguchi_tool` behaviour

```erlang
-callback name() -> binary().
-callback description() -> binary().
-callback input_schema() -> map().            %% a JSON Schema object
-callback call(Arguments :: map()) ->
    {ok, binary()} | {ok, [content()]} | {error, binary()}.

%% content() :: #{type => text, text => binary()}
```

A tool is a module. `call/1` may return a bare binary (wrapped as one text
block), a list of content blocks, or `{error, Message}`. Invocation is wrapped:
an `{error, _}` or a crash becomes an MCP tool error (`isError => true`) for that
call, never a server failure. v0.1 ships text content only; arguments are passed
through unvalidated (the tool pattern-matches what it needs).

### The pure dispatcher

```erlang
madoguchi:dispatch(Body :: binary() | map(), server()) -> {reply, map()} | noreply.

%% server() :: #{name := binary(), version := binary(), tools := [module()]}
```

`dispatch/2` decodes (when given a binary), routes the JSON-RPC message, and
returns either a response map to send back or `noreply` for a notification. It
is the single integration seam: the Cowboy handler, a Nova controller, a Plug,
or a test all call it the same way. Methods in v0.1: `initialize`, `ping`,
`tools/list`, `tools/call`, and `notifications/initialized` (a notification, so
`noreply`). JSON-RPC errors use the standard codes (`-32700` parse, `-32600`
invalid request, `-32601` method not found, `-32602` invalid params / unknown
tool). JSON-RPC batching is not supported - the `2025-06-18` revision removed it.

Notifications are detected by the absence of an `id` member (JSON-RPC), not by
method name, and always yield `noreply`.

### The Cowboy transport

`madoguchi_cowboy_h` is a `cowboy_handler`: POST reads the body, calls
`dispatch/2`, and replies `200 application/json` with the response or `202` for
a notification; other methods get `405`. The server is stateless - no sessions,
since tools are stateless and there are no subscriptions in v0.1.
`madoguchi:start_http/1,2` is a convenience that starts a Cowboy listener with
the MCP route mounted; consumers who run their own listener mount the handler
themselves.

### Framework integration is documented, not depended upon

The core depends on Cowboy (the bundled transport) but not on Nova. A Nova app
mounts MCP by calling `dispatch/2` from a ~12-line Nova controller - shown in
the getting-started guide - so it stays fully Nova-native without madoguchi
taking a Nova dependency. A future `madoguchi_nova` companion (the
arizona/arizona_nova pattern) will package that controller, a route helper, and
plugin-based auth; a `madoguchi_phoenix` Plug bridge could do the same for
Elixir. Those bridges belong in their own repos so the core reaches every BEAM
language and web stack.

## Consequences

**Positive.**

- Both ends of MCP now exist on the BEAM: gakudan calls servers, madoguchi
  builds them. They interoperate (same protocol revision).
- The pure dispatcher makes the protocol logic deterministic and socket-free to
  test, and lets the same core mount under Cowboy, Nova, Plug, or a future
  stdio loop.
- BEAM-wide: Elixir/Gleam/LFE author tools directly; any-language MCP clients
  consume the servers over the wire.

**Negative.**

- Cowboy is a hard dependency for the bundled transport even for consumers who
  would rather mount via Nova or Plug. Acceptable: an MCP server is inherently an
  HTTP server, and Cowboy underlies the BEAM web stack. The pure dispatcher
  remains usable without ever touching the handler.
- v0.1 covers tools only - no resources, prompts, stdio transport, sessions, or
  schema validation. Each is a later ADR. Tools are the dominant use case and the
  interop-critical path for gakudan's client.
