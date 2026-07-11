# ADR-0013: OS Patching & AMI Refresh

- **Status:** Accepted
- **Date:** 2026-07-11
- **Deciders:** James Moring (owner), Claude Code (architect)
- **Format:** Nygard ADR (Context · Decision · Consequences)

## Context

Nodes are cattle: they are **never patched in place**. OS patches follow the
immutable model — patch the golden **model instance**, bake a new AMI, roll it
out. Two things were unaddressed by the earlier ADRs:

1. The bake (ADR-0004) lays down Java/Keycloak/toolkit but never explicitly
   applies OS updates, so nothing guarantees an AMI is patched.
2. The upgrade strategy (ADR-0006) mandates a scale-to-0 cutover, but that was
   reasoned entirely around **Keycloak schema migration**. An OS-only patch
   changes no Keycloak version, so it triggers **no Liquibase migration** and
   carries **no mixed-version risk** — every node runs the same Keycloak version
   against the same schema and the same JGroups/Infinispan protocol.

That distinction is the key: the reason scale-to-0 exists does not apply to an
OS-only patch, so such a patch can roll out **zero-downtime and safely**,
without the `update-compatibility` machinery ADR-0006 deliberately avoided.

## Decision

### 1. OS patching is immutable — patch the model, never the fleet

OS updates are applied to the **model instance** at bake time; running ASG nodes
are never patched. There is no in-place `dnf update` on production nodes and no
configuration drift.

### 2. The bake applies OS updates (refines ADR-0004)

The golden-instance bake runs a **full `dnf -y update`** before `ami-clean` and
imaging, so every AMI is fully patched at build time. The `build-date` AMI tag
(ADR-0004) distinguishes a patch-only AMI from its predecessor at the same
Keycloak version.

### 3. Rollout mode is chosen by one question: did the Keycloak version change?

| Change | Rollout | Downtime |
|--------|---------|----------|
| **OS patch only** (same Keycloak version) | **rolling ASG instance refresh** | **zero** |
| **Keycloak version change** (schema may migrate) | scale-to-0 cutover (ADR-0006) | planned window |

The distinguishing test is purely the AMI's **Keycloak-version tag** vs. the
running one — no compatibility gating. **`kcadmin` treats this comparison as the
authoritative gate and refuses a rolling refresh when the Keycloak version tag
differs** (that case must use ADR-0006).

### 4. Rolling refresh mechanics (OS-only patch)

- Update the launch template to the new (patched) AMI.
- ASG **instance refresh** with a **minimum healthy percentage** and health-check
  grace, so capacity is maintained throughout.
- Replace a **canary** node first and run the ADR-0006 Phase 4 smoke test
  (health + reachability through the ALB) against it; on pass, let the refresh
  complete the fleet. New nodes join via JDBC_PING2 and register once
  `/health/ready` passes; old nodes drain from the ALB and terminate.
- Mixed old-AMI/new-AMI nodes coexisting during the refresh is safe because they
  run the **same Keycloak version**; DB-backed sessions (ADR-0009) survive node
  replacement.

### 5. Rollback is trivial (no schema involved)

Because an OS patch migrates no schema, rollback is simply: re-point the launch
template to the **previous AMI** and roll back with another instance refresh —
**zero-downtime, no RDS snapshot restore**. This is far simpler than ADR-0007's
Type B, which exists only for schema-migrating Keycloak upgrades.

### 6. Cadence and runbook

A regular patch cadence (routine monthly + out-of-band for critical CVEs):
patch model → rebuild AMI → rolling refresh. The step-by-step procedure lives in
`docs/operations/os-patching.md` (a follow-on deliverable, like the rollback
runbook).

## Consequences

### Positive

- Routine OS patching is **zero-downtime and safe**, so security patches can be
  applied often without a maintenance window.
- Fully immutable: no in-place patching, no drift; the fleet is always a clean
  image.
- Rollback is trivial and zero-downtime (previous AMI), with no DB involvement.
- The rolling-vs-scale-to-0 choice reduces to one authoritative tag comparison —
  no `update-compatibility` complexity.

### Negative / Trade-offs

- Two rollout mechanisms now exist (rolling for OS-only, scale-to-0 for Keycloak
  versions), both to document and test.
- **Mislabel risk:** rolling is only safe if the AMI truly is same-Keycloak-
  version. Rolling a version-changing AMI as "OS-only" would reintroduce exactly
  the mixed-version schema risk ADR-0006 avoids. Mitigated by making the
  Keycloak-version-tag comparison the authoritative, `kcadmin`-enforced gate.
- Frequent rebakes increase AMI churn; retention/cleanup (ADR-0004) must keep up.

### Notes

- Bake sequence and AMI tags → ADR-0004.
- Keycloak-version upgrades (scale-to-0) → ADR-0006.
- OS-patch runbook → `docs/operations/os-patching.md` (to be written).
- Cluster/session resilience during refresh → ADR-0009.
