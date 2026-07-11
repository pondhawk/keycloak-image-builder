# ADR-0008: Secrets Management

- **Status:** Accepted
- **Date:** 2026-07-11
- **Deciders:** James Moring (owner), Claude Code (architect)
- **Format:** Nygard ADR (Context · Decision · Consequences)

## Context

The AMI is environment-neutral and carries **no** secrets (§15, ADR-0004).
Every ephemeral ASG node must therefore obtain its secrets at boot. The secrets
KDT handles are:

- **Keycloak database credentials** (app user + password) — needed every boot.
- **Bootstrap admin credentials** — needed only when the database is
  uninitialized; near-vestigial for this populated-DB deployment, but must exist
  for correctness (ADR-0002, ADR-0005).

The blueprint fixes the store as **AWS Secrets Manager**. This ADR pins the rest:
what is a secret vs. plain config, how a secret reaches the Keycloak process
without ever touching persistent disk or the AMI, the IAM model, rotation, and
the DB-endpoint classification that finalizes the rollback runbook's Step 4.

Keycloak can read sensitive options either from **environment variables** or
from a **config keystore** (`KC_CONFIG_KEYSTORE`). The choice affects complexity.

## Decision

### What is a secret, and what is not

| Value | Classification | Source |
|-------|----------------|--------|
| DB app-user **username + password** | **Secret** | Secrets Manager: `keycloak/db` |
| Bootstrap admin username + password | **Secret** (transient) | Secrets Manager: `keycloak/bootstrap-admin` |
| RDS **endpoint / host / port / dbname** | **Not secret** | launch-template user-data → `keycloak.env` |
| ALB hostname (`KC_HOSTNAME`), JVM sizing | **Not secret** | user-data → `keycloak.env` |

The **RDS endpoint is not a secret.** This finalizes ADR-0007 Step 4: because
the endpoint lives in non-secret config, the **rename-swap** rollback method
(rename the restored instance back to the original identifier) preserves the
endpoint and requires **no change to any secret**. `KC_DB_URL` is composed at
boot from the non-secret host/port/dbname plus the vendor (ADR-0003).

### Delivery: fetch at boot → tmpfs env file → never persistent disk

The `keycloak-config.service` root oneshot (ADR-0005) does, on every boot:

1. Fetch both secrets from Secrets Manager using the instance's IAM role via
   **IMDSv2**.
2. Render **non-secret** runtime config into `/etc/keycloak/keycloak.env`.
3. Render **secret** values into `/run/keycloak/secrets.env` on **tmpfs**
   (memory-backed), mode `0640`, owner `root:keycloak`.
4. `keycloak.service` consumes **both** as `EnvironmentFile=` entries.

Because `/run` is tmpfs, secrets **never hit persistent disk** and vanish on
stop/terminate — so they cannot be captured into an AMI and `ami-clean` has
nothing secret to scrub on disk. Secrets are not written into
`/etc/keycloak/keycloak.env` (which is only non-secret config).

### Mechanism: environment variables, not a config keystore

Secrets are delivered as environment variables (`KC_DB_USERNAME`,
`KC_DB_PASSWORD`, and the bootstrap vars when applicable) via the tmpfs
`EnvironmentFile`. The Keycloak **config keystore** was considered and rejected:
it adds keystore creation and a keystore password (a chicken-and-egg secret) for
marginal benefit over a root-owned `0640` tmpfs file. Simplicity wins, with the
tmpfs + permissions + no-logging controls below as compensating protections.

### Bootstrap admin handling

Fetched only when the DB is uninitialized; written to `/run/keycloak/bootstrap.env`
(tmpfs), consumed by the init step, then removed (ADR-0002/0005). Normally a
no-op here (populated DB), and doubly safe by being tmpfs-only.

### IAM (least privilege)

- EC2 nodes run under an **instance profile / IAM role** — no static AWS keys on
  the instance.
- The role allows only `secretsmanager:GetSecretValue` on the **specific secret
  ARNs** (`keycloak/db`, `keycloak/bootstrap-admin`), plus `kms:Decrypt` on the
  CMK if those secrets use a customer-managed key.
- **IMDSv2 required** (tokens, restricted hop limit) so metadata/role creds are
  not trivially exfiltrated.

### Rotation

- Because nodes fetch at boot and are ephemeral, a rotated secret is picked up
  automatically by any newly launched node.
- Keycloak reads DB credentials at start, so rotating the DB password for a
  running fleet requires **cycling the nodes** (ASG instance replacement) — which
  the immutable model already makes routine. KDT does **not** implement live
  secret reload.

### No secret ever logged

`kcadmin` and the boot scripts must never echo or log secret values (strict-mode
scripts, no `set -x` over secret handling, redacted diagnostics). Secrets Manager
access is itself auditable via CloudTrail.

## Consequences

### Positive

- Secrets never touch persistent disk or the AMI: tmpfs delivery makes AMI
  neutrality structural rather than reliant on `ami-clean` scrubbing.
- Classifying the endpoint as non-secret makes rollback simpler and finalizes
  the runbook's riskiest step (rename-swap, no secret edits).
- Least-privilege IAM + IMDSv2 + no static keys keeps the blast radius of a
  compromised node small.
- Environment-variable delivery keeps the mechanism simple and debuggable
  without exposing secrets in config files.

### Negative / Trade-offs

- Env-var secrets are readable via `/proc/<pid>/environ` by root on the node;
  accepted, and bounded by node isolation and least privilege. The config
  keystore would reduce this but at a complexity cost we chose not to pay.
- DB-password rotation requires a node cycle rather than a hot reload — cheap
  under ASG, but not instantaneous.
- Two Secrets Manager entries and a user-data contract are moving parts that
  must be provisioned per environment (documented, not toolkit-created).

### Notes

- Boot orchestration and unit wiring → ADR-0005.
- Config layering (secret vs non-secret) → ADR-0002.
- `KC_DB_URL` composition and vendor split → ADR-0003.
- This ADR finalizes ADR-0007 Step 4 (endpoint is non-secret; rename-swap needs
  no secret change).
