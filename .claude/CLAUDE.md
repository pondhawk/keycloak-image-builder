# CLAUDE.md — Keycloak Deployment Toolkit (KDT)

Guidance for working in this repository.

## What this is

KDT is a **Bash CLI toolkit (`kcadmin`)** that installs, configures, validates,
and lifecycle-manages **Keycloak 26.x** on **Rocky Linux 10 / systemd / SELinux
Enforcing**, integrated with **AWS**. It builds an environment-neutral **golden
AMI** consumed by an **Auto Scaling Group**. It is orchestration glue — not a
service or a compiled app.

## Authority

- The **blueprint** (`Keycloak_Deployment_Toolkit_Architecture_Blueprint.md`) is
  the top-level spec.
- The **ADRs** (`docs/adr/`) record all architectural decisions and **win on
  specifics**. Read them before changing behavior. All 12 are Accepted.
- Do not introduce architecture that conflicts with an Accepted ADR; if a change
  needs to, write/supersede an ADR first (blueprint §21).

## Key decisions (see ADRs)

- Two DB engines, Postgres default + MySQL co-equal in tests (ADR-0003).
- Golden instance → `ami-clean` → per-vendor AMI → ASG self-configures at boot
  (ADR-0004, ADR-0005).
- Config split: neutral `keycloak.conf` baked; `keycloak.env` + secrets at boot
  (ADR-0002). Secrets from AWS Secrets Manager via tmpfs (ADR-0008).
- Immutable upgrade = scale-to-0 cutover; symlink swap is golden-instance-only
  (ADR-0006). Rollback via previous AMI + RDS snapshot (ADR-0007).
- Clustering via built-in `jdbc-ping` stack; TLS terminates at the ALB (ADR-0009).
- SELinux Enforcing, pragmatic (manage contexts, no bespoke domain) (ADR-0011).
- Testing = validate the toolkit's work at 3 gates, not test Keycloak (ADR-0012).

## Conventions

- Follow `.claude/coding-standards.md` for all Bash.
- Distribution: GitHub Action builds a versioned release tarball; the golden
  instance installs that (see `Makefile`, `.github/workflows/`).
- Milestones and status: `ROADMAP.md`.

## Build / check / test

- `make check` — ShellCheck + shfmt.
- `make test` — Bats.
- `make install` — install `kcadmin` onto a host (golden instance).
- `make package` — build the release tarball.
