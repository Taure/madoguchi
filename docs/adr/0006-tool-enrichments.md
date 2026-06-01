# 6. Tool enrichments: annotations, structured output, rich content

Date: 2026-06-01

## Status

Accepted.

## Context

The v0.1 tool primitive (ADR 0001) was deliberately minimal: `name`,
`description`, `input_schema`, `call`, and text-only content. The MCP spec lets a
tool say more about itself and return more than text:

- **Annotations and title.** Behavioural hints (read-only, destructive,
  idempotent, open-world) and a human display title help a client decide how to
  present or gate a tool (auto-run a read-only tool, confirm a destructive one).
- **Structured output.** A tool can declare an `outputSchema` and return
  `structuredContent` so callers get machine-readable results, not just prose.
- **Rich content.** Tool results can carry images, audio, links to resources,
  and embedded resources, not only text.

These are additive: existing four-callback tools must keep working untouched.

## Decision

Extend `madoguchi_tool` with optional callbacks and content helpers, and teach
the dispatcher to emit `structuredContent`.

### Optional callbacks

```erlang
-callback title() -> binary().
-callback annotations() -> annotations().
-callback output_schema() -> map().
-optional_callbacks([title/0, annotations/0, output_schema/0]).
```

`to_spec/1` includes each only when the module exports it, so a plain tool's
`tools/list` entry is unchanged. `annotations()` is a map of `title`,
`readOnlyHint`, `destructiveHint`, `idempotentHint`, `openWorldHint` - hints,
not guarantees.

### Structured output

`call/1` gains a third success shape, `{ok, [content()], Structured :: map()}`.
`invoke/2` passes it through and the dispatcher emits `structuredContent`
alongside `content`. A tool that returns the new shape should declare
`output_schema/0`; the framework does not validate the result against it.

### Rich content

`content()` widens from a single text shape to a union of text, image, audio,
resource_link, and embedded-resource blocks, with constructors `text/1`,
`image/2`, `audio/2`, `resource_link/2`, and `embedded/1`. Embedded resources
reuse the `madoguchi_resource` contents shape, so the two primitives compose.

The unknown-tool error message was also made generic (`"Unknown tool"`) rather
than echoing the client-supplied name.

## Consequences

**Positive.** Tools can describe their behaviour and return structured,
multi-modal results, matching what mainstream MCP clients expect, while the base
four-callback tool is completely unchanged (optional callbacks, additive content
union, additive result shape). Prompt messages, which reuse `content()`, gain the
rich blocks for free.

**Negative.** The framework trusts the tool: annotations are unverified hints and
structured output is not checked against `output_schema/0`. That keeps the core
small and matches the spec's "hints" framing; a validating layer can be added
later without changing these contracts. The widened `content()` type is a union,
so a consumer pattern-matching on the old single-shape type should match on
`type` going forward.
