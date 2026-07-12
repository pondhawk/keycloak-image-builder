# ADR-0007: Rollback Strategy

- **Status:** Accepted
- **Date:** 2026-07-11
- **Deciders:** James Moring (owner), Claude Code (architect)
- **Format:** Nygard ADR (Context · Decision · Consequences)

## Context

Rollback is the inverse of the scale-to-0 upgrade (ADR-0006) and reuses the
same mechanism: revert the ASG launch template to the **previous AMI** — the
retained rollback artifact (ADR-0004) — via scale-to-0 → scale-to-1 → smoke
test → scale-out. The binary side of rollback is therefore easy.

The database side is not, and this ADR exists to be honest about why:

1. **Schema migration is not reversible by code.** If the upgrade ran Liquibase
   migrations, the old version cannot safely run against the new schema.
   Binary-only rollback is then unsafe.
2. **The only DB recovery is the pre-upgrade RDS snapshot** (ADR-0006 Phase 2),
   and it has two hard properties:
   - **It is point-in-time.** Any data written *after* the snapshot — new user
     registrations, credential changes, sessions, admin edits — is **lost** on
     restore. The longer the new version served before rollback, the more is
     lost.
   - **Restore is not in-place.** RDS restores a snapshot to a **new instance
     with a new endpoint**; you cannot overwrite the running instance. Recovery
     therefore also requires repointing the DB endpoint (via the launch-template user-data /
     `keycloak.env`) or an RDS rename.

These realities, not the AMI swap, are what shape the strategy.

## Decision

### Two rollback types, selected by whether schema migrated

**Type A — AMI-only rollback (no schema change).**
Applies when the reverted change did not migrate schema: a same-Keycloak-version
AMI rebuild (config or custom-provider change), or a version change that
Liquibase applied no migrations for. Procedure — identical to an upgrade but
pointing at the older AMI:

1. Scale ASG to 0.
2. Revert the launch template to the previous AMI.
3. Scale to 1; smoke test (ADR-0006 Phase 4, both levels).
4. Scale out.

No database action, no data loss. Clean.

**Type B — version rollback with schema migration.**
Applies when the upgrade migrated schema. Binary revert alone is unsafe, so the
database must go back too:

1. Scale ASG to 0.
2. **Restore the pre-upgrade RDS snapshot** (Console) to a new instance.
3. **Repoint the DB endpoint** — update the value in the launch-template user-data /
   `keycloak.env` to the restored instance (or perform an RDS rename so the
   original endpoint name resolves to the restored data).
4. Revert the launch template to the previous AMI.
5. Scale to 1; smoke test; scale out.

**All data written after the Phase 2 snapshot is discarded.**

### Determining the type (conservative default)

`kcimage` decides A vs B by checking whether the upgrade applied Liquibase
changesets (new rows in Keycloak's `DATABASECHANGELOG`, or the known-migration
set for the version delta). **Default is conservative: treat any Keycloak
version change as schema-migrating (Type B) unless proven otherwise.** Only
same-version changes default to Type A.

### The decision window (when rollback is even the right move)

Because Type B loses post-snapshot writes, rollback is only *clean* while little
or no write traffic has occurred — i.e. **during the maintenance window or
immediately after**, before the new version serves meaningful production writes.
Past that point, KIB's guidance is to **forward-fix** (patch → new AMI → normal
upgrade) rather than roll back, because a snapshot restore would throw away real
production data. This guidance is documented, not enforced — the operator owns
the call.

### What is automated vs. manual

- **`kcimage` automates / verifies:** classifying A vs B; confirming the
  previous AMI and the pre-upgrade snapshot exist (pre-flight); driving the
  scale-to-0 → revert-template → scale-1 → smoke → scale-out sequence; the
  post-rollback smoke test.
- **Manual (Console), deliberately human:** the RDS snapshot **restore** and any
  endpoint rename — destructive, judgement-bearing operations kept out of
  automation (consistent with ADR-0004's manual-ops stance).

### Rollback validation

After rollback, the same two-level smoke test as an upgrade confirms the old
version runs cleanly against the (restored) database before scaling out.

### Operational runbook (mandatory)

Type B rollback **must** ship with a detailed, self-contained operational
runbook: `docs/operations/rollback-with-db-restore.md`. Because this procedure
runs rarely and under pressure, an administrator will never know it cold, so the
runbook is treated as a first-class deliverable, not an afterthought. It must:

- be **self-contained** — followable start to finish with no tribal knowledge;
- provide **copy-pasteable commands** with **expected outputs** at each step;
- mark explicit **decision points** (Type A vs B, proceed vs abort, rollback vs
  forward-fix) and the **point-of-no-return** data-loss warning inline;
- state the **new-endpoint repoint** step prominently (the riskiest action);
- be **rehearsed** — validated by a dry run against a restored snapshot in a
  non-production environment before it is relied upon, and re-validated when the
  procedure or tooling changes.

Type A rollback also gets a (shorter) runbook, but Type B is the one this
requirement is really about.

## Consequences

### Positive

- Rollback reuses the *exact* upgrade mechanism (scale-to-0 cutover) pointed at
  an older AMI — one procedure to learn, script, and test.
- The previous AMI is a known-good, immutable artifact, so binary rollback is
  fast and reliable.
- The mandatory pre-upgrade snapshot means even a schema-migrating upgrade has a
  recovery path — bounded, but real.
- A conservative A/B default errs toward data safety (assume migration).
- A rehearsed, self-contained runbook turns a rare, high-stakes operation into a
  followable procedure, removing reliance on an admin's memory in a crisis.

### Negative / Trade-offs

- Type B loses all writes since the snapshot; this is inherent to a shared DB +
  irreversible migration and cannot be engineered away here.
- RDS restore producing a new endpoint adds a repoint/rename step that must be
  done correctly under pressure — the riskiest manual action in the toolkit.
- The clean-rollback window is narrow; after it, forward-fix is the only
  data-preserving option, which operators must understand *before* an incident.
- Automating detection but not the restore leaves a human in the critical path
  by design — safer, but slower.

### Notes

- Pre-upgrade snapshot creation and the upgrade flow → ADR-0006.
- Previous-AMI retention → ADR-0004.
- DB endpoint delivery via launch-template user-data → ADR-0002,
  ADR-0008.
- Post-rollback cluster validation → ADR-0009.
- Detailed procedure → `docs/operations/rollback-with-db-restore.md` (the
  endpoint-repoint step is finalized once ADR-0008 fixes secret/endpoint
  delivery).
