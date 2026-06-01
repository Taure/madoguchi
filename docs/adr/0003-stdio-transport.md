# 3. stdio transport

Date: 2026-06-01

## Status

Accepted.

## Context

The dominant way to run a local MCP server is stdio: the client (Claude Code,
Cursor, a gakudan agent) launches the server as a subprocess and speaks
newline-delimited JSON-RPC over the child's stdin/stdout. ADR 0001 shipped only
the HTTP transport, which covers networked servers but not the local-launch case
that most adoption starts from. We want stdio without disturbing the pure
dispatcher.

The stdio binding has one hard rule: stdout carries only valid MCP messages.
Logs, banners, and diagnostics must go to stderr, or they corrupt the stream.

## Decision

A new `madoguchi_stdio` transport, a thin read loop over the existing pure
`madoguchi_dispatch:handle/2` (via `madoguchi:dispatch/2`). No protocol changes.

- `start/1` runs the loop in the calling process until EOF and returns `ok` -
  the entry point for an escript or a launched node.
- `start_link/1` spawns the loop in a linked process for supervision.
- `run/2` is the testable core: it takes the server and an `io_funs()` map of
  `read`/`write` funs. `read` returns one line (newline stripped) or `eof`;
  `write` emits one framed line. The production funs read from `standard_io` and
  write to `standard_io` with a trailing newline; tests inject funs over a list
  and a mailbox, so the transport is covered without a real port.

Each non-blank line is dispatched: a request yields exactly one response line, a
notification yields nothing, a malformed line yields a JSON-RPC parse error
(the dispatcher already produces this). Read errors are logged via `?LOG_ERROR`
to stderr (`logger`'s default handler), never written to stdout, and end the
loop as EOF.

## Consequences

**Positive.** Local MCP servers - the top adoption path - now work: point a
client's `command` at an escript that calls `madoguchi_stdio:start/1`. The pure
dispatcher is reused verbatim, so HTTP and stdio share one protocol
implementation and one test surface. `run/2`'s injected I/O makes the loop
deterministic to test.

**Negative.** The loop is synchronous and single-line-at-a-time; that matches
the stdio binding (one JSON-RPC document per line) and keeps ordering trivial.
Tool calls run inline in the loop process, so a slow tool blocks the next line;
acceptable for a local single-client server, and a consumer who needs
concurrency can dispatch off the loop. Anything a consumer prints to stdout
outside madoguchi will corrupt the stream - documented, not enforceable here.
