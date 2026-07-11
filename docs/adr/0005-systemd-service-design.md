# ADR-0005: systemd Service Design

- **Status:** Accepted
- **Date:** 2026-07-11
- **Deciders:** James Moring (owner), Claude Code (architect)
- **Format:** Nygard ADR (Context · Decision · Consequences)

## Context

Keycloak runs as a systemd service on Rocky Linux 10. The service must fit the
established model:

- The server is **pre-built** at bake, so nodes start with
  `kc.sh start --optimized` and do no build work at boot (ADR-0004).
- Config is split: neutral `keycloak.conf` is baked; `keycloak.env` (runtime,
  non-secret) and secrets are produced **at boot** (ADR-0002, ADR-0008).
- The AMI ships with **no** `keycloak.env` and no secrets, so every ephemeral
  ASG instance must fetch secrets and render its runtime environment on each
  boot before the server starts.
- SELinux is Enforcing and is the primary mandatory-access control (ADR-0011);
  systemd sandboxing is defense-in-depth, not the main control.

The unresolved questions this ADR settles: how many units, how boot-time
secret/env rendering is ordered relative to the server, which service user and
permissions apply, how readiness is judged, and how logging reaches journald.

Note on readiness: Keycloak (Quarkus) does not emit a systemd `sd_notify`
readiness signal by default. Readiness is therefore judged by its **health
endpoint** (`/health/ready`), which is also what the ALB target group checks —
not by systemd unit state.

## Decision

### Two units — privilege-separated, minimal

| Unit | Type | Runs as | Purpose |
|------|------|---------|---------|
| `keycloak-config.service` | `oneshot`, `RemainAfterExit=yes` | root | Boot-time prep: fetch secrets from Secrets Manager, render `/etc/keycloak/keycloak.env`, validate required runtime config, and handle the conditional bootstrap-admin case. |
| `keycloak.service` | `exec` | `keycloak` | The long-running server: `kc.sh start --optimized`. |

Two units (not one) because secret retrieval and writing `/etc/keycloak` need
root, while the server itself must run unprivileged. A oneshot keeps that
privileged work isolated and its failures individually visible
(`systemctl status keycloak-config`), rather than buried in `ExecStartPre` of
the main unit. Folding the bootstrap case into the config oneshot avoids a
third unit.

### Ordering and dependencies

```
network-online.target
        ↓  (After=, Wants=)
keycloak-config.service      # secrets → keycloak.env → validate → (bootstrap?)
        ↓  (After=, Requires=)
keycloak.service             # kc.sh start --optimized
```

- `keycloak.service` has `After=keycloak-config.service` and
  `Requires=keycloak-config.service`; if boot config fails, the server does not
  start (fail safe — blueprint principle 5).
- Both order `After=network-online.target` (RDS + Secrets Manager need network).
- Both are **enabled but not started** in the AMI (`ami-clean` stops them); the
  ASG instance starts them at boot.

### Service user and file access

- Dedicated system user/group `keycloak` (no login shell).
- `/opt/keycloak/current` — read/execute only (installs are immutable).
- `/etc/keycloak` — read (written by the root oneshot, read by the server).
- `/var/lib/keycloak`, `/var/log/keycloak` — read/write (runtime state).

### Config wiring (from ADR-0002)

- `KC_CONFIG_FILE=/etc/keycloak/keycloak.conf` is set in the unit `Environment`,
  pointing Keycloak at `/etc/keycloak` so **no config lives inside the immutable
  install tree**.
- `keycloak.service` uses `EnvironmentFile=/etc/keycloak/keycloak.env` (and,
  only when present, `bootstrap.env`). JVM sizing comes through
  `JAVA_OPTS_APPEND` in `keycloak.env`, not by editing units.

### Bootstrap-admin handling

`keycloak-config.service` provisions `bootstrap.env` (temporary admin creds from
Secrets Manager) **only when the database is uninitialized**; after successful
init the file is removed (ADR-0002). Because this deployment consumes an
already-populated RDS (project scope), this path is normally a **no-op** — it
exists for greenfield correctness and is guarded so repeated/parallel boots are
safe.

### Readiness, restart, and health

- Unit "started" ≠ "ready." Readiness is the `/health/ready` endpoint, polled by
  the ALB target group and by `kcadmin status`/`health`.
- `Restart=on-failure` with `RestartSec` and a start-limit, for transient
  faults. A persistently unhealthy node fails its ALB check and is replaced by
  the ASG — systemd restarts are not the recovery path for hard failures.

### Logging

- `StandardOutput=journal` / `StandardError=journal`; Keycloak logs to console
  and journald captures it (`journalctl -u keycloak`), satisfying §13. Structured
  logging format and any file appender/rotation are set in `keycloak.conf` and
  detailed in ADR-0010.

### Hardening (defense-in-depth, subordinate to SELinux)

A conservative baseline that does not break the JVM or `kc.sh`:
`NoNewPrivileges=yes`, `ProtectSystem=strict` with `ReadWritePaths=` for
`/var/lib/keycloak` and `/var/log/keycloak`, `ProtectHome=yes`,
`PrivateTmp=yes`. More aggressive directives are adopted only if validated
against Keycloak under SELinux Enforcing (ADR-0011), since SELinux is the
primary control.

### Packaging

- Base units live in the repo `systemd/`; `kcadmin install` places them, runs
  `systemctl daemon-reload`, and enables both.
- Environment-specific tuning uses **drop-ins**
  (`/etc/systemd/system/keycloak.service.d/`), never edits to the base unit.

## Consequences

### Positive

- Clean privilege separation: secret handling is root and isolated; the server
  is unprivileged.
- Boot ordering makes "config must succeed before the server starts" a
  structural guarantee, not a script convention.
- Ephemeral-instance reality (render env every boot) is handled without baking
  anything environment-specific into the AMI.
- Readiness via the health endpoint aligns systemd, the ALB, and `kcadmin`
  on one definition of "ready."

### Negative / Trade-offs

- Two units plus drop-ins are more moving parts than a single unit; justified by
  privilege separation and failure isolation, but it is more to document.
- The bootstrap-admin path is near-vestigial for this populated-DB deployment
  yet must still be implemented and tested for correctness.
- Health-based (not `sd_notify`) readiness means systemd reports "active" before
  Keycloak is actually serving; operators and the ALB must rely on
  `/health/ready`, which must be clearly documented to avoid confusion.
- Conservative sandboxing leaves some hardening on the table pending SELinux
  co-validation.

### Notes

- Secret retrieval mechanism and IAM → ADR-0008.
- Logging format/rotation → ADR-0010.
- SELinux contexts for units and paths, and sandboxing co-validation → ADR-0011.
- `kcadmin` subcommands (`start`/`stop`/`status`/`logs`/`journal`/`health`)
  wrap these units.
