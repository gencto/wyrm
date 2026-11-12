# Security policy

WYRM runs on plant networks and commands real devices. A flaw in it can move a valve, so we take
reports seriously and answer them first.

## Supported versions

WYRM is before 1.0. Only the newest code on `main` and the newest official links release
(`links-v*`) get fixes. There are no back-ports to older releases yet.

## Report a vulnerability

Do not open a public issue, discussion or pull request for a vulnerability.

1. Open <https://github.com/gencto/wyrm/security/advisories/new> (GitHub private vulnerability
   reporting). Only the maintainers see the report.
2. Say what is affected (crate, link, Studio, gateway, wire protocol), the version or commit, and
   the steps that show the problem. A proof of concept against the demo (`examples/demo`) or a
   simulator is enough; do not test against systems that are not yours.
3. Say whether and how you want to be credited.

What happens next:

- We confirm the report within 3 working days.
- We send a first assessment (severity, affected parts) within 10 working days.
- We fix critical and high findings first and publish a GitHub security advisory with the fix.
  We agree the publication date with you; the default is at most 90 days after the report.

## In scope

- `wyrmd` (router, admin, ACL generator, gateway, flow engine, historian, storage, peers, standby).
- The SDKs and tools in this repository: `wyrm-client`, `wyrm-link-sdk`, `wyrm-ffi`, the Dart
  packages, `wyr`, `wyrm-mcp`, `wyrm-agent`.
- Every link under `links/` and every official link package.
- WYRM Studio (`studio/`).
- The wire format and token rules in `spec/` (a flaw in the design counts).

Out of scope: Eclipse Zenoh itself (report to the Zenoh project), third-party links from other
repositories, and setups that turn off protection on purpose (`insecure_plaintext: true`, the
`rest` plugin outside profile `dev`, `allow_all_links` on an open network).

## What already protects users

- Threat model and controls: [`docs/security/threats.md`](docs/security/threats.md); findings of the
  security review and what happened to each: [ADR 0031](docs/adr/0031-security-review-2026-10-31.md).
- Accepted dependency advisories, each with its reason: [`.cargo/audit.toml`](.cargo/audit.toml).
  `cargo audit` runs on every push and every day.
- Official link packages carry SHA-256 sums in the index the broker checks, and build provenance
  you can verify with `gh attestation verify` ([`docs/links.md`](docs/links.md), §12a).
