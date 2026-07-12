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
a **single JSON secret per cluster** holding all environment-specific config, a
non-sensitive **user-data pointer** to it (so multiple clusters coexist), how the
values reach the Keycloak process without ever touching persistent disk or the
AMI, the IAM model, and rotation.

Keycloak can read sensitive options either from **environment variables** or
from a **config keystore** (`KC_CONFIG_KEYSTORE`). The choice affects complexity.

## Decision

### One JSON secret per cluster

All of a cluster's environment-specific configuration — endpoint, hostname, JVM
sizing, **and** credentials — lives in a **single JSON secret per cluster** in
AWS Secrets Manager, e.g. `keycloak/<cluster>/config`:

```json
{
  "db_url": "jdbc:mysql://cluster-a-rds.internal:3306/keycloak",
  "db_username": "keycloak_app",
  "db_password": "••••••",
  "hostname": "https://auth-a.example.com",
  "java_opts_append": "-Xms512m -Xmx1024m",
  "bootstrap_admin_username": "••••••",
  "bootstrap_admin_password": "••••••"
}
```

**One secret per cluster** (not a fixed convention name) so multiple Keycloak
clusters can coexist in one AWS account without colliding.

### The user-data pointer (a name, not a credential)

Each cluster's launch template conveys **only the secret's name/ARN** in
user-data — a non-sensitive pointer, never a credential:

```
KDT_SECRET_ID=keycloak/<cluster>/config
```

Putting a *name* in user-data is safe; putting a *password* there would not be
(readable via IMDS/SSRF and by anyone with launch-template read access). So the
password never goes in user-data — only the pointer does. This keeps the model
flexible for N clusters while every actual value stays in Secrets Manager.

### Per-instance facts from IMDS

The node's **private IP** (JGroups bind address, ADR-0009) is unique per
instance, so it is read from **IMDSv2** at boot — not from the shared cluster
secret.

### Delivery: fetch one secret → split by sensitivity → tmpfs for secrets

The `keycloak-config.service` root oneshot (ADR-0005) does, on every boot:

1. Read `KDT_SECRET_ID` from user-data and the private IP from **IMDSv2**.
2. `secretsmanager:GetSecretValue` on that **one** secret (instance IAM role).
3. Write **non-secret** fields (`db_url`, `hostname`, `java_opts_append`) plus the
   private IP into `/etc/keycloak/keycloak.env`.
4. Write **secret** fields (`db_username`, `db_password`, and — only when the DB
   is uninitialized — the bootstrap admin) into `/run/keycloak/secrets.env` on
   **tmpfs**, mode `0640`, owner `root:keycloak`.
5. `keycloak.service` consumes both as `EnvironmentFile=` entries.

Because `/run` is tmpfs, secrets **never hit persistent disk**, cannot be
captured into an AMI, and vanish on stop/terminate. `db.vendor` is *not* in the
secret — it is build-time, baked into the per-vendor AMI (ADR-0003); the
`db_url`'s `jdbc:` prefix must match that vendor.

### Mechanism: environment variables, not a config keystore

Secrets are delivered as environment variables (`KC_DB_USERNAME`,
`KC_DB_PASSWORD`, and the bootstrap vars when applicable) via the tmpfs
`EnvironmentFile`. The Keycloak **config keystore** was considered and rejected:
it adds keystore creation and a keystore password (a chicken-and-egg secret) for
marginal benefit over a root-owned `0640` tmpfs file. Simplicity wins, with the
tmpfs + permissions + no-logging controls below as compensating protections.

### Bootstrap admin handling

The bootstrap admin username/password are **fields in the same cluster secret**.
They are written to `/run/keycloak/secrets.env` (tmpfs) only when the DB is
uninitialized, consumed by the init step, then cleared (ADR-0002/0005). Normally
a no-op here (populated DB), and doubly safe by being tmpfs-only.

### IAM (least privilege)

- EC2 nodes run under an **instance profile / IAM role** — no static AWS keys on
  the instance.
- The role allows only `secretsmanager:GetSecretValue` on **that cluster's secret
  ARN**, plus `kms:Decrypt` on the CMK if it uses a customer-managed key.
  Per-cluster scoping means one cluster's node role cannot read another cluster's
  secret, even though the name is known (it is in user-data).
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
- One secret per cluster + a name-only user-data pointer is both flexible
  (N clusters) and secure (no credential ever in user-data); boot is a single
  fetch.
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
- Per cluster you provision one JSON secret + one user-data pointer + one IAM
  role (documented, not toolkit-created). Non-secret config (endpoint, hostname)
  living inside a Secrets Manager secret is slightly unconventional, but buys the
  single-fetch simplicity.

### Notes

- The boot fetch uses the **AWS CLI v2** and **`jq`**, installed on the model as
  documented prerequisites (README) and baked into the AMI. KDT does not install
  third-party tooling; AWS CLI v2 is not in the RHEL repos (official bundle),
  `jq` is (`dnf`).
- Boot orchestration and unit wiring → ADR-0005.
- Config layering (secret vs non-secret) → ADR-0002.
- Vendor split (`db.vendor` is build-time, not in the secret) → ADR-0003.
- ADR-0007 Step 4 (rename-swap): rename-swap preserves the endpoint, so the
  secret's `db_url` stays valid and needs **no edit**; a true repoint means
  editing the secret's `db_url`.
