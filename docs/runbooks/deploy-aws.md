# Runbook — Deploy to AWS

Take a **sealed model instance** (the output of any model-instance runbook),
create a golden AMI, wire the launch template + user-data, and roll it to your
Auto Scaling Group.

> **This runbook runs on the AWS side** (Console / CLI), not on the model
> instance. It assumes you have already reached **✅ ready for image creation**
> via [Fresh install](fresh-install.md), [Upgrade](upgrade-install.md),
> [OS patch](os-patch.md), or [Clean install](clean-install.md).

Pick your path:

- [Part A — Create the AMI](#part-a--create-the-ami) (always)
- [Part B — Launch template & user-data](#part-b--launch-template--user-data) (first deploy, and whenever config changes)
- [Part C — Roll it out](#part-c--roll-it-out): [first deploy](#c1--first-deployment) · [OS patch (rolling)](#c2--os-patch--rolling-instance-refresh) · [Keycloak upgrade (scale-to-0)](#c3--keycloak-upgrade--scale-to-0-cutover)

---

## Part A — Create the AMI

1. **EC2 → Instances →** select the sealed model instance **→ Actions → Image
   and templates → Create image.**
2. Give it a name that encodes the lineage, e.g. `keycloak-26.1.4-postgres`.
3. **Tag the AMI** (these tags are how rollout mode is decided later):

   | Tag | Example | Why |
   |-----|---------|-----|
   | `keycloak-version` | `26.1.4` | Distinguishes an upgrade from an OS patch (ADR-0006/0013) |
   | `db-vendor` | `postgres` | The vendor is baked in; don't mix vendors in one ASG |
   | `arch` | `aarch64` | The AMI inherits the model's CPU arch; the ASG must use matching instance types |
   | `build-date` | `2026-07-12` | Distinguishes a patch-only AMI from its predecessor at the same version |

4. Wait for the AMI state to become **Available**.

> One AMI is **one DB vendor**. If you run both Postgres and MySQL, build and
> deploy each from its own model/AMI lineage.

> The AMI's **architecture matches the model instance you built on** — confirm it
> with `kcimage version` (or the `arch` line in `verify`). An **ARM64/aarch64**
> image requires **Graviton** instance types (e.g. `t4g`, `m7g`, `c7g`) in the
> launch template and ASG; an **x86_64** image requires x86 types (e.g. `t3`,
> `t3a`, `m7i`). KIB can't cross-build, so build the model on the arch you intend
> to run.

---

## Part B — Launch template & user-data

The node is environment-neutral; **everything environment-specific arrives here,
as launch-template user-data.** At boot, `configure-node.sh` (baked into the AMI)
reads user-data + the node's private IP from IMDSv2 and splits it into
`/run/keycloak/keycloak.env` and `/run/keycloak/secrets.env` — both on tmpfs, so
nothing environment-specific ever touches disk — no AWS CLI, no secrets store.

### User-data format

Plain `KEY=VALUE` lines using Keycloak's native `KC_*` names, one per line.

| Key | Required | Handling | Notes |
|-----|:---:|----------|-------|
| `KC_DB_URL` | ✅ | env | JDBC URL to your DB; vendor prefix **must match** the AMI's `db-vendor` |
| `KC_DB_USERNAME` | ✅ | **secret** → tmpfs | DB user |
| `KC_DB_PASSWORD` | ✅ | **secret** → tmpfs | DB password |
| `KC_HOSTNAME` | ✅ | env | The **ALB** public URL (e.g. `https://auth.example.com`) — issuer, redirects, and Admin Console are built from this, **not** the instance address |
| `KC_BOOTSTRAP_ADMIN_USERNAME` | optional | **secret** → tmpfs | First-boot temporary admin; remove after initial setup |
| `KC_BOOTSTRAP_ADMIN_PASSWORD` | optional | **secret** → tmpfs | " |
| `KC_LOG_LEVEL` | optional | env | Overrides the image's baked `warn` default — e.g. `info` to debug a node, or per-category `warn,org.keycloak:info` |
| *(any other `KC_*`)* | optional | env | Passed through to `keycloak.env` |
| `KC_CACHE_EMBEDDED_NETWORK_BIND_ADDRESS` | — | injected | **Do not set** — the boot script fills it from the node's private IP for `jdbc-ping` |

The boot script **refuses to start** if any of the four required keys is missing.

### Example (PostgreSQL AMI)

```ini
KC_DB_URL=jdbc:postgresql://mydb.abc123.us-east-1.rds.amazonaws.com:5432/keycloak
KC_DB_USERNAME=keycloak
KC_DB_PASSWORD=REPLACE_ME
KC_HOSTNAME=https://auth.example.com
```

For a MySQL AMI, only the URL prefix/port change:

```ini
KC_DB_URL=jdbc:mysql://mydb.abc123.us-east-1.rds.amazonaws.com:3306/keycloak
```

### Networking the launch template / security groups

- **ALB → node:** HTTP `8080` (app) and `9000` (management/health) — TLS
  terminates at the ALB; nodes serve plain HTTP with `proxy-headers=xforwarded`.
- **node ↔ node:** `7800` and `57800` for the `jdbc-ping` cluster (ADR-0009).
- **node → database:** `5432` (Postgres) or `3306` (MySQL) to your DB.
- **ALB listener:** `443` with your TLS certificate; target group forwards to
  node `8080`, health check on `9000` `/health/ready`.

Set the launch template's **AMI** to the one from Part A and paste the user-data
above.

---

## Part C — Roll it out

### C.1 — First deployment

1. Create the **target group** (HTTP `8080`, health check `/health/ready` on
   `9000`) and the **ALB** (HTTPS `443` → target group).
2. Create the **Auto Scaling Group** using the launch template, across your
   private subnets, attached to the target group.
3. Scale to your desired capacity. Nodes boot, `configure-node.sh` writes their
   config, `keycloak.service` starts, they form a `jdbc-ping` cluster and
   register with the ALB once `/health/ready` passes.
4. Browse `KC_HOSTNAME` and confirm the Admin Console loads over TLS.

### C.2 — OS patch (rolling instance refresh)

Use this when the new AMI has the **same `keycloak-version` tag** as the running
one (built via the [OS patch](os-patch.md) runbook). Zero downtime, no RDS
snapshot (ADR-0013).

1. Update the **launch template** to the new (patched) AMI.
2. Start an **ASG instance refresh** with a **minimum healthy percentage** and a
   health-check grace period, so capacity holds throughout.
3. Let it replace a **canary** node first; smoke-test it through the ALB
   (`/health/ready`, Admin Console). On pass, let the refresh complete the fleet.
4. **Rollback** (if needed): re-point the launch template to the previous AMI and
   run another instance refresh. No schema was touched, so this is
   zero-downtime.

> The refresh path **refuses to proceed if the AMI's `keycloak-version` tag
> differs** from the running fleet — that is a schema-migrating change and must
> use C.3.

### C.3 — Keycloak upgrade (scale-to-0 cutover)

Use this when the new AMI has a **different `keycloak-version` tag** (built via
the [Upgrade](upgrade-install.md) runbook). This has a **planned downtime
window** and a **mandatory RDS snapshot** (ADR-0006/0007).

1. **Take an RDS snapshot** — this is your rollback artifact. Do not skip it.
2. **Scale the ASG to 0.** All old-version nodes terminate; no node can touch the
   DB until the new version comes up. *(Downtime window begins.)*
3. **Update the launch template** to the new AMI.
4. **Scale the ASG to 1.** One new-version node boots, applies the Liquibase
   schema migration, and registers with the ALB. With exactly one node, routing
   is deterministic.
5. **Smoke-test** that single node through the ALB (issuer/redirects/Admin
   Console all use `KC_HOSTNAME`).
6. On pass, **scale back up** to full capacity. *(Downtime window ends.)*
7. **Rollback** (if the smoke test fails): re-point the launch template to the
   **previous AMI**, and **restore the RDS snapshot** if the migration ran. Full
   procedure: [`docs/operations/rollback-with-db-restore.md`](../operations/rollback-with-db-restore.md).

---

## See also

- [ADR-0004](../adr/0004-ami-and-build-strategy.md) — AMI & build strategy
- [ADR-0006](../adr/0006-upgrade-strategy.md) — scale-to-0 upgrade
- [ADR-0008](../adr/0008-secrets-management.md) — node config & secrets via user-data
- [ADR-0009](../adr/0009-clustering-jdbc-ping2.md) — clustering & TLS at the ALB
- [ADR-0013](../adr/0013-os-patching-and-ami-refresh.md) — OS patching & AMI refresh
