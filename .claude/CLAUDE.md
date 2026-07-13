# CLAUDE.md — Keycloak Image Builder (KIB)

Guidance for working in this repository.

## What this is

KIB is a **Bash CLI toolkit (`kcimage`)** that installs, configures, validates,
and lifecycle-manages **Keycloak 26.x** on **RHEL-family 10 (Rocky/Alma/RHEL) / systemd / SELinux
Enforcing**, integrated with **AWS**. It builds an environment-neutral **golden
AMI** consumed by an **Auto Scaling Group**. It is orchestration glue — not a
service or a compiled app.

## Authority

- The **blueprint** (`Keycloak_Image_Builder_Architecture_Blueprint.md`) is
  the top-level spec.
- The **ADRs** (`docs/adr/`) record all architectural decisions and **win on
  specifics**. Read them before changing behavior. All 13 are Accepted.
- Do not introduce architecture that conflicts with an Accepted ADR; if a change
  needs to, write/supersede an ADR first (blueprint §21).

## Key decisions (see ADRs)

- Two DB engines, Postgres default + MySQL co-equal in tests (ADR-0003).
- Golden instance → `seal` → per-vendor AMI → ASG self-configures at boot
  (ADR-0004, ADR-0005).
- Config split: neutral `keycloak.conf` baked into `/opt/keycloak/conf` (native,
  no `KC_CONFIG_FILE`); `keycloak.env` + secrets injected at boot onto tmpfs
  `/run/keycloak` (ADR-0002). From launch-template user-data (ADR-0008).
- Everything server-side lives under `/opt/keycloak` — one version, no versioned
  subdir, no `current` symlink; only tmpfs `/run/keycloak` outside (ADR-0001).
- Immutable upgrade = scale-to-0 cutover; the model-instance `upgrade` is a safe
  swap (old kept until the new version builds, then deleted; rollback on failure)
  (ADR-0006). Rollback via previous AMI + RDS snapshot (ADR-0007).
- Clustering via built-in `jdbc-ping` stack; TLS terminates at the ALB (ADR-0009).
- SELinux Enforcing, pragmatic (manage contexts, no bespoke domain) (ADR-0011).
- Testing = validate the toolkit's work at 3 gates, not test Keycloak (ADR-0012).

## Conventions

- Follow `.claude/coding-standards.md` for all Bash.
- Distribution: GitHub Action builds a versioned release tarball; the golden
  instance installs that (see `Makefile`, `.github/workflows/`).
- Milestones and status: `ROADMAP.md`.

## Build / check / test (developer machine only)

- `make check` — ShellCheck + shfmt.
- `make test` — Bats.
- `make package` — build the release tarball.

There is no `make install`. On the model instance you run `./scripts/kcimage`
straight from the extracted tarball; `kcimage install` bakes the runtime (Java,
distribution, config, `kc.sh build`, systemd units + boot script, SELinux).
`make` is not needed on the model instance.
