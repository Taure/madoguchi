# Architecture Decision Records

The decision log for madoguchi. Each ADR captures the *why* behind a behaviour,
a wire-protocol choice, or a contract - the context an agent or contributor
needs before changing it.

## When to write one

Write a new ADR for any new behaviour, capability, transport, or change to an
existing contract (a behaviour callback, a public API shape, the wire format).
Small fixes and refactors that preserve contracts do not need one.

Use the [Nygard format](https://github.com/joelparkerhenderson/architecture-decision-record):
**Context** (the forces), **Decision** (what we chose), **Consequences** (the
trade-offs). Number sequentially; never rewrite a merged ADR - supersede it
with a new one.

## Index

| ADR | Title |
| --- | --- |
| [0001](0001-mcp-server-core.md) | MCP server core |
| [0002](0002-http-transport-security.md) | HTTP transport security and interop guards |
