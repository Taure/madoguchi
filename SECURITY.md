# Security

## Transport hardening

The bundled HTTP transport (`madoguchi_http_handler`, `madoguchi:start_http/2`)
enforces the MCP Streamable HTTP security and interop MUSTs:

- **Origin validation (DNS-rebinding protection).** A present `Origin` header
  must be allowed. Default policy `same_host` accepts only same-host origins;
  configure `allowed_origins` (`any` or an explicit list) to widen it. A rejected
  origin gets `403`.
- **Loopback bind by default.** `start_http/2` binds `127.0.0.1` unless `ip` is
  set, so a local server is not exposed on every interface. Set
  `ip => {0, 0, 0, 0}` to bind all interfaces deliberately.
- **Protocol-version check.** A present `MCP-Protocol-Version` header that names
  an unsupported revision gets `400`.
- **Accept negotiation.** A present `Accept` that does not admit
  `application/json` gets `406`.

Client-facing error bodies are generic; rejection details are logged via
`?LOG_*` reports and never leaked to the client. A token-verification seam for
authorization is planned; a full OAuth authorization server is out of scope and
belongs in a companion.

## Reporting

Report vulnerabilities privately via GitHub Security Advisories on this
repository. Please do not open public issues for security reports.

## Dependency advisories

CI runs `rebar3 audit` and fails on any advisory of severity `low` or higher.
Advisories that have no upstream fix and do not apply to madoguchi are listed
here and skipped via the `audit-ignores` CI input. Each entry is revisited when
an upstream fix ships.

| Advisory | Dependency | Severity | Why it does not apply |
| --- | --- | --- | --- |
| [GHSA-g2wm-735q-3f56](https://github.com/advisories/GHSA-g2wm-735q-3f56) (CVE-2026-43969) | cowlib (transitive via cowboy) | low | Cookie request-header injection in `cow_cookie:cookie/1`. madoguchi serves JSON-RPC over POST, sets no cookies, and never calls `cow_cookie`. No upstream fix is available (vulnerable range `>= 2.9.0, <= 2.16.1`); remove this entry once cowlib ships a patched release. |
