# 5. Prompts

Date: 2026-06-01

## Status

Accepted.

## Context

Prompts are the third MCP server primitive: named, parameterised message
templates a client lists (`prompts/list`) and instantiates (`prompts/get`),
typically surfaced as slash commands or quick actions. With tools (ADR 0001) and
resources (ADR 0004) in place, prompts complete the three server primitives a
general MCP client expects.

The primitive should match the others: a behaviour the host implements,
collected in the server definition, dispatched by the pure core, crash-isolated.

## Decision

A `madoguchi_prompt` behaviour and two methods on the pure dispatcher.

### Behaviour

```erlang
-callback name() -> binary().
-callback description() -> binary().
-callback arguments() -> [argument()].      %% optional
-callback get(Arguments :: map()) ->
    {ok, [message()]} | {ok, binary(), [message()]} | {error, binary()}.
```

A prompt is a module. `name/0` and `description/0` feed `prompts/list`;
`arguments/0` (optional via `-optional_callbacks`) declares named arguments and
is included in the list entry only when non-empty. `get/1` renders the prompt
from the decoded arguments and returns the messages, optionally with a
description, or `{error, Message}`. Helper constructors `user/1`, `assistant/1`,
and `message/2` build messages, reusing `madoguchi_tool:text/1` so message
content shares the tool content shape. Prompts are listed in the server
definition under `prompts`.

### Methods

- `prompts/list` -> aggregated `to_spec/1` across prompt modules.
- `prompts/get` -> looks the prompt up by name and renders it. An unknown name
  maps to JSON-RPC `-32602`; a render failure or crash maps to `-32603` with a
  generic client message, the detail logged via `?LOG_ERROR`.

`initialize` advertises `prompts => #{}` in capabilities only when the server
defines at least one prompt. Capability advertising for resources and prompts
now shares one `maybe_cap/3` helper.

### Isolation

`madoguchi_prompt:get/2` catches render crashes and turns them into a
`{error, _}`, the same discipline as tools and resources.

## Consequences

**Positive.** All three MCP server primitives now exist on the BEAM with one
consistent shape (behaviour + server-definition list + pure dispatch + crash
isolation + helper constructors). The dispatcher stays pure and fully unit
tested. Prompt messages reuse the tool content type, so widening content (ADR
0006) widens prompts for free.

**Negative.** Argument validation is the prompt's responsibility - the framework
passes the raw arguments map and the prompt pattern-matches what it needs, the
same trade-off as tools. Completion of prompt arguments
(`completion/complete`) is not included; it is a separate capability and ADR.
