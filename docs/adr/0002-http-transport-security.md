# 2. HTTP transport security and interop guards

Date: 2026-06-01

## Status

Accepted.

## Context

The v0.1 Cowboy handler (ADR 0001) read the body and dispatched it without
inspecting request headers. The MCP Streamable HTTP transport and the JSON-RPC
binding place several MUSTs on the server that are HTTP-header concerns, not
protocol-logic concerns:

1. **DNS-rebinding protection.** A local MCP server reachable from a browser is
   a rebinding target: a malicious page can point `fetch` at `127.0.0.1` and,
   without an `Origin` check, drive the server. The spec requires servers to
   validate the `Origin` header.
2. **Local exposure.** A server bound to `0.0.0.0` is reachable from the whole
   network. For a local MCP server (the common case) that is an unnecessary
   exposure.
3. **Protocol-version interop.** After initialization, a client sends an
   `MCP-Protocol-Version` header. A server that does not speak the named version
   must reject the request rather than silently mis-handle it.
4. **Content negotiation.** A POST carrying a request must accept
   `application/json`.

These belong in the transport: the pure dispatcher
(`madoguchi_dispatch:handle/2`) sees decoded messages, never headers, and must
stay transport-free and unit-testable.

## Decision

The checks live in `madoguchi_http_handler`, run in order before the body is
dispatched. The dispatcher is untouched; it only gains
`madoguchi_dispatch:supported_versions/0` so the transport knows which versions
are acceptable.

- **Origin.** When an `Origin` header is present it must be allowed. The default
  policy `same_host` accepts only origins whose host matches the request host;
  `any` disables the check; a list of binaries allows an explicit set. A rejected
  origin gets `403` and is logged (`mcp_origin_rejected`). An absent `Origin`
  (non-browser clients) is allowed.
- **Bind address.** `start_http/2` defaults `ip` to `{127, 0, 0, 1}`. Operators
  set `{0, 0, 0, 0}` to bind all interfaces deliberately.
- **MCP-Protocol-Version.** A present header is checked against
  `supported_versions/0`. An unsupported value gets `400` and is logged
  (`mcp_unsupported_protocol_version`). The `initialize` request negotiates its
  version in-band, so its header (if any) is not gated here; an absent header is
  allowed for backward compatibility.
- **Accept.** A present `Accept` that does not admit `application/json` (directly
  or via `*/*` / `application/*`) gets `406`. An absent header is allowed.

Rejections return a JSON-RPC error envelope so a client that parses the body
still gets a structured failure. Client-facing messages are generic; details go
to the log via `?LOG_*` reports, never to the client.

Options reach the handler because `start_http/2` now mounts the handler with
`{Server, Opts}` state; the handler accepts a bare `Server` too, so a
hand-mounted route keeps working with default policy.

## Consequences

**Positive.** The server meets the transport security and interop MUSTs;
local servers are loopback-only by default; the pure dispatcher stays pure and
the guards are covered by socket-level tests.

**Negative.** A consumer that mounts the handler by hand and wants a non-default
origin policy must mount it as `{Server, Opts}` rather than a bare `Server`.
The `same_host` default rejects cross-origin browser callers; that is the
intended posture, and `allowed_origins` opens it deliberately.
