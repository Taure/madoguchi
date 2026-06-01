# AGENTS.md

Working agreement for agents and contributors on **madoguchi** (窓口, "service
window") - an MCP server framework for the BEAM. It lets any Erlang service
expose tools to Model Context Protocol clients (Claude Code, Cursor, gakudan
agents). A small OTP library: bring-your-own tools, mount the transport in your
own app.

## Ecosystem

Part of a BEAM-native multi-agent stack (all under https://github.com/Taure):

- **[gakudan](https://github.com/Taure/gakudan)** - agent orchestration
  runtime; ships the MCP *client*.
- **[saiten](https://github.com/Taure/saiten)** - runtime-agnostic eval/scoring
  + CI gate.
- **madoguchi** - MCP *server* framework: expose any BEAM service as MCP tools.
- **[sekisho](https://github.com/Taure/sekisho)** - LLM gateway / control plane:
  virtual keys, budgets, and audit in front of Anthropic + OpenAI (chat **and
  embeddings**) + Vertex.
- **[bunko](https://github.com/Taure/bunko)** - agent memory + RAG (pgvector).
- **[banto](https://github.com/Taure/banto)** - multi-agent repo concierge; the
  showcase consumer that wires the pillars together.

Gakudan sister libs: **gakudan_metrics**, **gakudan_otel**, **gakudan_tickets**
(+ **gakudan_tickets_github**), **gakudan_liveboard**.

**This repo** is the MCP *server* side. With gakudan's MCP client it covers both
halves of MCP on the BEAM. The core is transport-agnostic (the bundled Cowboy
handler `madoguchi_http_handler`) so any web stack can mount it; a Nova bridge is
deferred until a consumer needs it.

## Design pillars

- **Primitives, not a framework.** Behaviours (`madoguchi_tool`,
  `madoguchi_resource`, `madoguchi_prompt`), a pure JSON-RPC dispatcher, and two
  transports (Cowboy `madoguchi_http_handler`, stdio `madoguchi_stdio`).
- **Transport-agnostic core.** `madoguchi_dispatch:handle/2` is a pure function:
  decoded JSON-RPC message in, response out. It needs no HTTP, so it is tested
  by feeding it messages - deterministic, no sockets. Keep it pure.
- **Spec-faithful.** Streamable HTTP and stdio transports, JSON-RPC 2.0, MCP
  protocol version `2025-11-25`, negotiating `2025-06-18` for older clients
  (the revision gakudan's MCP client speaks, so the two interoperate).
- **Secure by default.** The HTTP transport binds loopback, validates `Origin`
  (DNS-rebinding protection), and enforces `Accept` / `MCP-Protocol-Version`.
  Client-facing errors stay generic; detail goes to `?LOG_*` reports.
- **Pluggable primitives.** A tool / resource provider / prompt is a module
  implementing the matching behaviour; pass the lists in the server definition.

## Scope - what belongs here

- **In:** the `madoguchi_tool`, `madoguchi_resource`, and `madoguchi_prompt`
  behaviours; the JSON-RPC dispatcher (initialize, ping,
  notifications/initialized, tools/list, tools/call, resources/list,
  resources/templates/list, resources/read, prompts/list, prompts/get); the
  Cowboy Streamable HTTP handler + `start_http/stop_http`; the stdio transport
  (`madoguchi_stdio`).
- **Out (deferred):** a `madoguchi_nova` bridge; a token-verification seam for
  authorization; server-initiated SSE (GET stream); resource/prompt
  subscriptions; completion (`completion/complete`); input-schema validation.
- **Out forever:** the MCP client (that is gakudan's MCP client); sampling,
  roots, elicitation (client features); the legacy HTTP+SSE transport; JSON-RPC
  batching; a bundled OAuth authorization server; experimental Tasks; anything
  that warps the library for a single consumer.

## Commands

```bash
rebar3 compile
rebar3 eunit
rebar3 fmt          # erlfmt (write); CI runs fmt --check
rebar3 xref
rebar3 dialyzer
rebar3 ex_doc       # fix any new warnings
```

## Pre-push checklist

`fmt --check` -> `xref` -> `dialyzer` -> `eunit`, all green.

## Conventions

- OTP 29+. The `~"..."` sigil for binaries, never `<<"...">>`.
- No `lists:foldl/foldr` - list comprehensions + `maps:from_list`, or explicit
  named recursion.
- JSON via the OTP `json` module, never thoas/jiffy.
- Docs: OTP `-moduledoc` / `-doc`; ex_doc guides under `docs/`.
- `{vsn, "git"}` in `.app.src` - the version derives from git tags.
- Default to zero comments; comment only non-obvious *why*.

## Extension points (behaviours)

- `madoguchi_tool` - `name/0`, `description/0`, `input_schema/0`, `call/1`, plus
  optional `title/0`, `annotations/0`, `output_schema/0`, `icons/0`.
- `madoguchi_resource` - `list/0`, optional `templates/0`, `read/1`.
- `madoguchi_prompt` - `name/0`, `description/0`, `get/1`, plus optional
  `arguments/0`, `icons/0`.

Implement the matching behaviour in your own module and list it in the server
definition (`tools`, `resources`, `prompts`).

## Decisions live in ADRs

Before changing a behaviour, the wire protocol, or a contract, read
[docs/adr/](docs/adr/). Write a new ADR (Nygard format) for any new behaviour,
capability, transport, or contract change.

## Git and PRs

Conventional commits (`feat:`, `fix:`, `chore:`, `docs:`, `test:`, `refactor:`).
Always open a PR - never push to `main`. Every merge to `main` tags a release,
so keep each PR coherent.
