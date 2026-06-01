# 4. Resources and resource templates

Date: 2026-06-01

## Status

Accepted.

## Context

ADR 0001 shipped tools only. Resources are the second MCP server primitive: a
way to expose readable context (files, records, generated documents) that a
client can list and fetch by URI. The spec also defines resource *templates* -
parameterised URIs (`mem://doc/{id}`) a client can expand. gakudan's client and
general MCP clients both consume resources, so a BEAM MCP server needs them.

The design must mirror the tool primitive: a behaviour a host implements,
collected in the server definition, dispatched by the pure core, with crashes
isolated.

## Decision

A `madoguchi_resource` behaviour and three methods on the pure dispatcher.

### Behaviour

```erlang
-callback list() -> [resource()].
-callback templates() -> [template()].   %% optional
-callback read(Uri :: binary()) ->
    {ok, [contents()]} | {error, not_found} | {error, binary()}.
```

A provider is a module. `list/0` returns static resource descriptors;
`templates/0` (optional via `-optional_callbacks`) returns URI-template
descriptors; `read/1` returns the contents for a URI, `{error, not_found}` for
an unknown URI, or `{error, Message}` for a failure. Helper constructors
`text/2` and `blob/3` build the contents blocks. Providers are listed in the
server definition under `resources`.

### Methods

- `resources/list` -> aggregated `list/0` across providers.
- `resources/templates/list` -> aggregated `templates/0`.
- `resources/read` -> the first provider that serves the URI wins; `not_found`
  from all providers maps to JSON-RPC `-32002` (resource not found); a missing
  `uri` param maps to `-32602`; a read failure or crash maps to `-32603` with a
  generic client message, the detail logged via `?LOG_ERROR`.

`initialize` advertises `resources => #{}` in capabilities only when the server
defines at least one provider, so a tools-only server is unchanged.

### Isolation

`madoguchi_resource:read/2` catches provider crashes and turns them into a
`{error, _}` read failure, the same discipline as tool invocation: one bad
provider read never takes down the dispatch.

## Consequences

**Positive.** Servers can expose context, not just actions; the primitive
matches tools exactly (behaviour + server-definition list + pure dispatch +
crash isolation), so the mental model and test discipline carry over. The
dispatcher stays pure and gains full unit coverage for all three methods.

**Negative.** `read/1` is given the raw URI; template expansion/matching is the
provider's job, not the framework's. That keeps the core small and lets a
provider match however it likes (prefix, regex, a real router), at the cost of
not validating a read against the advertised templates. Subscriptions
(`resources/subscribe`, `notifications/resources/updated`) are not included;
they need server-initiated messaging, a later ADR.
