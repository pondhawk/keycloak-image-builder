# ADR-0012: Testing

- **Status:** Accepted
- **Date:** 2026-07-11
- **Deciders:** James Moring (owner), Claude Code (architect)
- **Format:** Nygard ADR (Context · Decision · Consequences)

## Context

The blueprint (§16) lists a broad testing program (Bats, install/upgrade/
cluster/rollback suites, "every milestone adds tests"). A full multi-layer,
both-engine, multi-node CI apparatus was considered and judged **too complex for
the value** at this project's scale. Instead, testing is deliberately scoped to
the two moments that actually carry risk, both of which KIB already performs as
built-in `kcimage` operations:

1. **The golden image** — is it functionally correct *and* safely neutral before
   it becomes an AMI?
2. **A freshly deployed node** — does it actually work once the ASG brings it up?

This is acceptance/validation testing at the right checkpoints, not a regression
suite. The trade-off is accepted (see Consequences) and consciously narrows §16.

**Scope — we are not testing Keycloak.** KIB tests validate that **the toolkit
did its job**: install, configure, neutralize, deploy, and wire up clustering
and the reverse-proxy/hostname setup. Keycloak's own correctness (OIDC, login,
token issuance) is covered upstream and is **out of scope** — KIB checks that
Keycloak is **healthy and reachable with the configuration KIB applied**, not
that Keycloak's auth logic behaves.

## Decision

### 1. Cheap static hygiene (kept — nearly free)

- **ShellCheck** on all scripts (errors fail).
- **shfmt** for consistent formatting.

These cost almost nothing and catch real scripting defects; they stay.

### 2. Golden-image validation — before and after `seal`

Two gates on the golden instance, both run by `kcimage`:

**Before `seal` — functional correctness (`kcimage verify`):**
- Java present and correct version; `kc.sh build` succeeded; `start --optimized`
  works.
- Service starts; `/health/ready` and `/health/live` pass; the endpoints KIB
  configured are reachable and reflect KIB's config (e.g. OIDC discovery issuer
  equals the configured hostname) — a config check, not a Keycloak-behavior test.
- SELinux **Enforcing** with correct contexts; systemd units valid; config
  renders correctly.

**After `seal` — neutrality (the security-critical gate):**
- No secrets on disk (`/run` clear, `bootstrap.env` gone); `keycloak.env` reset
  to template — no real endpoints/hostnames.
- `machine-id` truncated; SSH host keys removed; logs, backups, realm exports,
  shell history cleared.
- Service **enabled but stopped**.
- The gate **fails the bake** if any residual secret or environment-specific
  value remains (ADR-0004).

Passing both is the definition of "ready to image."

### 3. Post-deploy smoke test — after ASG scale to 1

Reusing ADR-0006 Phase 4, `kcimage` runs a **simple but effective** two-level
smoke test on the single new node:

- **Node-local:** `/health/ready`, `/health/live` — the process KIB deployed is
  up and connected to the DB with the URL/credentials KIB wired.
- **Through the ALB (reachability + KIB's config, not Keycloak's behavior):** the
  node answers through the ALB; OIDC discovery returns the **expected issuer =
  ALB hostname** (validates KIB's `hostname` / `proxy-headers` setup); the Admin
  Console endpoint is reachable. We do **not** perform login/token flows — that
  exercises Keycloak's functionality, which is not KIB's to test.

Pass → scale out (`kcimage cluster` then confirms the node joined — validating
KIB's JDBC_PING2 / bind-address / security-group wiring). Fail → roll back. This
is the gate for every deploy and every upgrade.

### 4. Engine coverage falls out naturally

Each AMI is single-vendor, so building and validating a Postgres AMI validates
Postgres, and building a MySQL AMI validates MySQL — no separate CI matrix is
needed. Both engines are still exercised, just at bake time for whichever AMI is
being produced.

### 5. What we deliberately do NOT build

- No multi-node cluster CI, no mocked-command unit-test apparatus as a
  requirement, no automated upgrade/rollback suites in CI.
- The rare, AWS-shaped operations (scale-to-0 upgrade, Type B rollback with RDS
  restore) rely on the **rehearsed runbooks** (ADR-0007) plus the smoke test —
  not on automated coverage.

### 6. "Every milestone adds tests" — reinterpreted

Each milestone **extends the `kcimage verify` / neutrality / smoke checks** that
apply to it, rather than adding a separate test tier. Green ShellCheck/shfmt and
passing `kcimage verify` are the merge/Definition-of-Done gates (§20).

## Consequences

### Positive

- Simple and understandable: three concrete gates (pre-clean verify, post-clean
  neutrality, post-deploy smoke) instead of a five-layer pyramid.
- Effort concentrates on the two highest-risk moments — publishing an image and
  serving from a new node.
- The security-critical neutrality gate is retained in full.
- The same checks serve install, upgrade, and rollback, so there is one thing to
  learn and maintain.
- Scope stays honest and small — validating the toolkit's own work, not
  re-testing Keycloak, so checks don't duplicate upstream coverage or bloat.

### Negative / Trade-offs

- **Weak regression protection.** Without unit/integration suites, a script
  change can break behavior that no test catches until `kcimage verify` or a
  smoke test fails during a bake or deploy — later and more expensively than a
  unit test would.
- Upgrade and rollback correctness leans on **manual runbook rehearsal**
  (ADR-0007) and human discipline, not automation.
- Cluster-formation bugs may not surface until a real multi-node deploy, since
  there is no multi-node test harness.
- This consciously delivers **less** than blueprint §16; the reduction is an
  accepted, owner-approved simplification, revisitable if the project grows.

### Notes

- `kcimage verify` scope → ADR-0004, ADR-0006.
- Neutrality gate → ADR-0004.
- Smoke test → ADR-0006.
- Rollback rehearsals → ADR-0007.
