# ADR-0006: Upgrade Strategy

- **Status:** Accepted
- **Date:** 2026-07-11
- **Deciders:** James Moring (owner), Claude Code (architect)
- **Format:** Nygard ADR (Context · Decision · Consequences)

## Context

Upgrades are immutable and canonical: a new version is prepared on the golden
instance, baked into a new AMI (per vendor), and rolled into production by
replacing instances — never by mutating live nodes (blueprint §10, ADR-0004).
The side-by-side install + `current` symlink swap exists **only on the golden
instance** to prepare and validate a version before baking.

The hard part of any Keycloak upgrade is the **shared database**. All nodes
share one RDS instance; the new version runs Liquibase schema migrations
against it on startup. Two facts dominate:

1. **Schema migration is effectively irreversible.** DB rollback is never
   automatic; recovery is an RDS snapshot restore (ADR-0007).
2. **Mixed-version operation is unsafe.** If an old-version node runs against a
   schema an incompatible new version has migrated, it can error or corrupt
   data.

The simplest way to make (2) a non-issue is to **guarantee that only one
version ever touches the database** — i.e. take the whole cluster down before
introducing the new version. This accepts a short, planned downtime in exchange
for a single, always-safe path with nothing to detect, gate, or coordinate. The
owner has explicitly accepted hard downtime as reasonable for this system.

## Decision

### One strategy: scale-to-zero cutover

There is exactly one production upgrade path. No rolling upgrade, no blue/green,
no compatibility gating.

#### Phase 1 — Version preparation (golden instance, offline)

1. Install the new Keycloak version side-by-side under
   `/opt/keycloak/keycloak-<new>`.
2. Deploy custom assets from `/opt/keycloak-custom`; run `kc.sh build` for the
   AMI's `db.vendor`.
3. `kcadmin verify` — offline checks (Java, build success, units, SELinux
   contexts).
4. Switch the `current` symlink to the new version **on the golden instance
   only**; re-validate.
5. `ami-clean` → create the new per-vendor AMI(s) in the AWS Console (ADR-0004).

#### Phase 2 — Pre-upgrade RDS snapshot (mandatory)

Take an RDS snapshot; it is the rollback artifact (ADR-0007). The snapshot is a
Console action, but `kcadmin` **pre-flight verifies a recent snapshot exists and
refuses to proceed otherwise**. Fail-safe, not convenience.

#### Phase 3 — Cutover (the downtime window begins)

1. **Scale the ASG to 0.** All old-version nodes terminate. No Keycloak node is
   now running — this is what makes the upgrade safe: the database can only be
   touched by the version brought up next.
2. **Update the launch template** to the new AMI.
3. **Scale the ASG to 1.** One new-version node boots, applies any Liquibase
   schema migration, and registers with the ALB target group normally. Because
   exactly one node is registered, ALB routing to it is deterministic.

#### Phase 4 — Smoke test the single node

The node's application URLs (issuer, redirect URIs, Admin Console) are built
from the **ALB hostname** (`KC_HOSTNAME`), not the instance address, so a
realistic functional test must go through the ALB — which is safe here because
the single registered node receives all of that traffic. Two levels:

- **Level 1 — node-local (hostname-independent):** `kcadmin health` on the
  instance checks `/health/ready` + `/health/live` on the management port —
  process up, DB connected, schema migration applied.
- **Level 2 — through the ALB hostname:** OIDC discovery (issuer = ALB
  hostname), a test login + token flow, and Admin Console availability, all via
  the ALB URL, deterministically routed to the single new node.

The cluster is expected to be size 1 here — not a failure (ADR-0009).

- **Pass** → proceed to Phase 5.
- **Fail** → roll back (ADR-0007): revert the launch template to the previous
  AMI and, because schema may have migrated, restore the Phase 2 snapshot.

#### Phase 5 — Scale out (the downtime window ends)

**Scale the ASG to the desired capacity** (the smoke-tested node is already
registered). New nodes launch from the new AMI, join via JDBC_PING2, and pass
ALB health checks.
`kcadmin cluster` confirms membership and size. Upgrade complete.

### Downtime

The window runs from "scale to 0" (Phase 3) until the smoke test passes and
capacity is restored (Phase 5) — essentially one node's boot + migration +
validation time. This is planned, announced downtime and is accepted.

## Alternatives considered and rejected

- **Rolling upgrade (ASG instance refresh, node-by-node).** Zero-downtime but
  only safe across schema-compatible versions; would require gating every
  upgrade with `kc.sh update-compatibility` and risk a mixed-version window if
  misjudged. Rejected: too much machinery for the benefit.
- **Blue/green (new ASG + new target group, flip ALB).** Zero-downtime at the
  HTTP layer, but the shared RDS means the old (blue) fleet can break the moment
  green migrates the schema unless the change is backward-compatible — so it
  *also* needs a compatibility check, plus duplicate ASG/target-group
  plumbing. Rejected: complexity without escaping the shared-DB constraint.

Both remain theoretically available if zero-downtime ever becomes a hard
requirement, but they are explicitly **not** part of this toolkit.

## Consequences

### Positive

- One upgrade path, always safe: scaling to 0 structurally guarantees no
  mixed-version operation against the database — nothing to detect or gate.
- Trivial to understand, document, script, and test; matches the immutable-AMI
  model exactly (just swap the launch template between two scalings).
- The single-node smoke test is a real checkpoint before full scale-out, with a
  clear pass/fail and a defined rollback.
- The mandatory snapshot pre-flight keeps the one irreversible step (schema
  migration) recoverable.

### Negative / Trade-offs

- Every upgrade incurs a hard downtime window. Accepted for this system, but it
  is a genuine service interruption that must be scheduled and communicated.
- No in-place or zero-downtime option ships; a future need for one is a new,
  larger piece of work (and reintroduces the compatibility concerns above).
- Rollback after a schema migration still requires an RDS snapshot restore —
  the smoke test limits blast radius but does not make migration reversible.

### Notes

- Rollback mechanics and snapshot restore → ADR-0007.
- Cluster validation (size-1 acceptance, membership) → ADR-0009.
- AMI lineage and Console imaging this depends on → ADR-0004.
