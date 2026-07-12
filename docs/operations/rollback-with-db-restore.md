# Runbook: Full Rollback with Database Restore (Type B)

> **Status: DRAFT.** Illustrative commands below are finalized during
> implementation; the DB-endpoint method is now fixed by ADR-0008 (rename-swap,
> endpoint is non-secret). This runbook must be **rehearsed** against a restored
> snapshot in a non-production environment before it is relied upon (ADR-0007).

**Applies to:** rolling a Keycloak cluster back to the previous version **after
a schema migration has occurred** (Type B in [ADR-0007](../adr/0007-rollback-strategy.md)).
For a config/provider or no-migration rollback, use the shorter Type A runbook —
no database action is needed there.

**Audience:** the on-call administrator. This document assumes **no prior
memory** of the procedure. Follow it top to bottom.

---

## ⚠️ Read this before you start

1. **DATA LOSS.** Restoring the pre-upgrade snapshot discards **every write made
   after the snapshot was taken** — new user registrations, password/credential
   changes, sessions, and admin edits. The longer the new version has been
   serving, the more you lose.
2. **POINT OF NO RETURN / decide fast.** Type B is only a *clean* option during
   or shortly after the upgrade window. If the new version has been serving real
   production traffic for a while, **STOP** — prefer a forward-fix (patch → new
   AMI → normal upgrade). Rolling back then trades a bug for permanent data loss.
3. **DOWNTIME.** This procedure takes the whole cluster down. Announce a
   maintenance window.
4. **NEW ENDPOINT.** An RDS restore creates a **new database instance**. You must
   either rename it back to the original endpoint or repoint config at it
   (Step 5). This is the step most likely to go wrong — go slowly.

**Decision gate — do not proceed unless all are true:**

- [ ] The problem cannot be resolved by a forward-fix in acceptable time.
- [ ] The upgrade **migrated the schema** (if unsure, `kcimage` reports this; if
      still unsure, assume yes — Type B).
- [ ] The amount of data written since the snapshot is acceptable to lose.
- [ ] A maintenance window is announced/authorized.

---

## Prerequisites (gather these first)

- [ ] **Pre-upgrade RDS snapshot** identifier (from ADR-0006 Phase 2). Record it:
      `________________________`
- [ ] **Previous AMI** id (the rollback target). Record it: `________________`
- [ ] Current DB instance identifier + endpoint. Record: `________________`
- [ ] AWS Console access with RDS + EC2 Auto Scaling permissions.
- [ ] The ALB hostname for smoke testing: `________________`
- [ ] `kcimage` access on a management/bastion host.

Run the pre-flight check (verifies the snapshot and previous AMI exist):

```
kcimage rollback --preflight        # illustrative
# Expected: "snapshot <id> found; previous AMI <id> found; OK to proceed"
```

- [ ] Pre-flight reports **OK**. If not, resolve before continuing.

---

## Procedure

### Step 1 — Announce and begin the maintenance window
- [ ] Post the maintenance notice. Record start time: `________`

### Step 2 — Scale the ASG to 0
- [ ] EC2 → Auto Scaling Groups → *(your ASG)* → **Edit** → Desired **0**, Min
      **0**. Save.
- [ ] Wait until **0 running instances** and the ALB target group shows no
      healthy targets.
- [ ] Confirm no Keycloak node is running. **This must be true before Step 3** —
      no old node may touch the database while it is being replaced.

### Step 3 — Restore the pre-upgrade snapshot to a new instance
- [ ] RDS → Snapshots → select the pre-upgrade snapshot → **Restore snapshot**.
- [ ] Restore with the **same** engine/version, instance class, subnet group,
      parameter group, and security groups as the original. Give it a temporary
      name, e.g. `<original>-restore`.

```
# illustrative equivalent
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier <original>-restore \
  --db-snapshot-identifier <pre-upgrade-snapshot-id> \
  --db-subnet-group-name <subnet-group> \
  --vpc-security-group-ids <sg-id>
```

- [ ] Wait until the restored instance is **Available**.

### Step 4 — ⚠️ Make the restored data reachable at the expected endpoint
> **Method (per ADR-0008): rename-swap.** The RDS endpoint is non-secret config,
> so renaming the restored instance back to the original identifier preserves the
> endpoint and requires **no change to any secret or to `keycloak.env`**.

Rename-swap:
- [ ] Rename the current (post-upgrade) instance `<original>` → `<original>-bad`.
- [ ] Rename the restored instance `<original>-restore` → `<original>`.
- [ ] Wait for both renames to finish; confirm the endpoint DNS for `<original>`
      now resolves to the restored instance.

*Alternative (repoint):* update the DB endpoint in Secrets Manager /
`keycloak.env` to the restored instance's endpoint instead of renaming. Use only
if the rename-swap is not viable.

- [ ] Confirm connectivity to the intended endpoint (e.g. `kcimage check --db`).

### Step 5 — Revert the launch template to the previous AMI
- [ ] EC2 → Launch Templates → *(your template)* → **Create new version** with
      the **previous AMI** id recorded above. Set the ASG to use it (Latest or
      that version).
- [ ] Double-check the AMI id matches the previous version (and correct
      `db.vendor`).

### Step 6 — Scale to 1 and let it come up
- [ ] Set ASG Desired **1**, Min **1**. Save.
- [ ] Wait for one instance to launch and the node to start. It runs against the
      restored (old-schema) database with the old version — no migration should
      occur.

### Step 7 — Smoke test the single node (both levels)
- [ ] **Level 1 (node-local):** on the instance, `kcimage health` →
      `/health/ready` and `/health/live` pass; DB connected.
- [ ] **Level 2 (through the ALB hostname):** OIDC discovery issuer = ALB
      hostname; a test login + token succeeds; Admin Console loads.
- [ ] **Pass?**
  - [ ] **Yes** → Step 8.
  - [ ] **No** → **STOP.** Do not scale out. Capture logs and escalate; the
        database is already restored, so re-evaluate (retry, different snapshot,
        or forward-fix).

### Step 8 — Scale out to desired capacity
- [ ] Set ASG Desired/Min back to normal (record values: `______`).
- [ ] Confirm all nodes healthy in the ALB target group.
- [ ] `kcimage cluster` → membership and size match expected.

### Step 9 — Close the window
- [ ] Announce service restored. Record end time: `________`.

---

## Post-rollback cleanup (after confirming stability)

- [ ] Keep `<original>-bad` (the post-upgrade instance) for a defined hold period
      for forensics, then delete it.
- [ ] Retain the pre-upgrade snapshot until the rollback is confirmed durable.
- [ ] File an incident note: what failed, data-loss window, follow-up fix.

## Rehearsal record

This runbook is only trustworthy if rehearsed. Log dry runs:

| Date | Performed by | Environment | Outcome / notes |
|------|--------------|-------------|-----------------|
|      |              |             |                 |
