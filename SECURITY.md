# Security

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
