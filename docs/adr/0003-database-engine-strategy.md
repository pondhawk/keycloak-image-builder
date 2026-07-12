# ADR-0003: Database Engine Strategy

- **Status:** Accepted
- **Date:** 2026-07-11
- **Deciders:** James Moring (owner), Claude Code (architect)
- **Format:** Nygard ADR (Context · Decision · Consequences)

## Context

The immediate driver for KIB is moving and upgrading an existing production
Keycloak whose state lives in **Amazon RDS for MySQL**. That instance stays on
MySQL for the foreseeable future — no engine conversion is bundled with the
upgrade (the owner has already validated the data migration by hand). At the
same time, PostgreSQL is Keycloak's reference database: best-tested upstream,
the assumed target for some newer features, and the engine with the most
battle-tested locking behavior for JDBC_PING2 cluster discovery.

We therefore need a strategy that keeps the owner's live MySQL workload
first-class while pointing new deployments at the stronger long-term default,
**without forking the toolkit into two codebases.**

Two facts from earlier ADRs constrain this:

- The database vendor is a Keycloak **build-time** option (`--db`), so it is
  baked into the AMI and is the *sole* reason KIB produces per-vendor AMIs
  (ADR-0002, ADR-0004).
- KIB **never creates databases** and begins at an already-provisioned,
  already-populated RDS instance (project scope). It consumes connection
  details; it does not own schema creation or data loading.

## Decision

### Support both PostgreSQL and MySQL as first-class engines

The database engine is a single **configuration axis, `db.vendor`**, with two
supported values: `postgres` and `mysql`. Both are first-class:

- **PostgreSQL is the documented default** for new / greenfield nodes.
- **MySQL is co-equal in test and hardening coverage** — it is not a
  best-effort tier. The §16 test suites (install, upgrade, cluster, rollback)
  run against **both** engines in the CI matrix. This is non-negotiable because
  the owner's production workload runs on MySQL.

`db.vendor` selects one AMI variant at bake time; a given running node is
always single-vendor. There is no runtime engine switching.

### Engine is the only fork point; everything else is shared

The toolkit is one codebase. Engine-specific behavior is confined to a small,
enumerated set of branch points, each isolated behind `db.vendor`:

| Branch point | Postgres | MySQL | Where it lives |
|---|---|---|---|
| `kc.sh build --db` value | `postgres` | `mysql` | AMI bake (ADR-0004) |
| JDBC driver | bundled with distribution | bundled with distribution | no manual step¹ |
| `KC_DB_URL` template | `jdbc:postgresql://…` | `jdbc:mysql://…` | boot / `keycloak.env` |
| JDBC_PING2 discovery table DDL (dialect) | Postgres types | MySQL types | clustering (ADR-0009) |
| Connectivity / charset validation | `SELECT 1`; encoding checks | `SELECT 1`; **`utf8mb4`** charset + collation; `sql_generate_invisible_primary_key`=OFF (MySQL 8.0.30+) | validation (§12) |

¹ Verified against the Keycloak 26.x documentation (2026-07-11): database
drivers ship with Keycloak for all supported engines **except Oracle** (which
KIB does not support). No per-vendor driver-provisioning step is required, so
this is not in fact a fork point — recorded here to close the question.

Everything else — directory layout, config hierarchy, systemd, SELinux,
symlink-swap version prep, immutable upgrade, CLI surface, validation flow — is
engine-neutral and shared.

### Supported versions

Keycloak 26.x supports both engines. Exact tested version floors (e.g. MySQL
8.x, a recent PostgreSQL major) are pinned during implementation against the
26.x supported-database matrix and the owner's actual RDS versions. MySQL
schemas must use `utf8mb4`; validation enforces this rather than assuming it,
since KIB consumes a pre-existing database. Additionally, **MySQL 8.0.30+ must
have `sql_generate_invisible_primary_key` disabled** (an RDS parameter-group
setting) or Keycloak schema initialization and Liquibase upgrade migrations
fail; validation checks this too (verified against the 26.x docs, 2026-07-11).

### Explicitly out of scope

- Creating databases, schemas, users, or loading data.
- MySQL → PostgreSQL conversion. A future, separate effort could add a
  `kcimage migrate-db` command (realm export/import based); it is **not** part
  of this strategy or the current move/upgrade.

## Consequences

### Positive

- The owner's live MySQL system is a supported, fully-tested target from day
  one, not a downgraded path.
- New deployments get Keycloak's strongest-supported engine by default, giving
  a clean long-term direction without stranding MySQL.
- A single codebase with an enumerated, small fork surface keeps maintenance
  cost low and makes "what differs per engine?" answerable by reading one table.
- Consuming an existing populated RDS (no DB creation) sharply reduces the
  toolkit's blast radius and privilege requirements.

### Negative / Trade-offs

- The CI matrix doubles the DB dimension: every install/upgrade/cluster/rollback
  suite runs twice. Test infrastructure must provision both a Postgres and a
  MySQL RDS (or compatible) target.
- Two AMIs to bake, publish, and lifecycle per release (ADR-0004), with the
  discipline to keep them in lockstep.
- MySQL carries known sharp edges Postgres does not (charset/collation,
  possible manual driver provisioning, less-exercised JDBC_PING2 locking);
  these must be actively tested rather than assumed.
- Requiring `utf8mb4` on a database KIB does not own means validation can only
  *detect and refuse*, not fix — a misconfigured source DB blocks bring-up.

### Notes

- Per-vendor AMI mechanics and driver provisioning → ADR-0004.
- JDBC_PING2 discovery-table DDL per dialect → ADR-0009.
- `KC_DB_*` delivery and secret handling → ADR-0002, ADR-0008.
- Decision recorded in project memory (`kdt-db-engine-strategy`).
