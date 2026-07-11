# Changelog

All notable changes to KDT are documented here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/); versioning is SemVer.

## [Unreleased]

### Added
- Milestone 1: all 12 Architecture Decision Records (`docs/adr/`), Accepted.
- Type B rollback runbook (`docs/operations/rollback-with-db-restore.md`).
- Milestone 2: repository scaffolding — `kcadmin` dispatcher, `lib/` helpers,
  systemd units, config templates, SELinux fcontext, Bats test, Makefile,
  GitHub Actions (CI + release), `.claude/` standards.
- Milestone 3: `kcadmin install` — ensures OpenJDK, the service user, the
  directory tree (ADR-0001), and a side-by-side Keycloak distribution with
  `current` symlink management. Idempotent, dry-run aware; Bats-tested.
- Milestone 3: `kcadmin check` — read-only host prerequisite validation
  (Java, systemd, SELinux Enforcing, DNS, commands, optional RDS TCP; §12).
- Milestone 4: `kcadmin configure` — render `keycloak.conf` (neutral, vendor
  substituted) and `keycloak.env` (from the environment via `envsubst`) into
  `/etc/keycloak`, with an ADR-0002 neutrality guard. `--etc-dir` override,
  dry-run aware; Bats-tested.
- Milestone 5: systemd integration — `lib/systemd.sh` + `start`/`stop`/`restart`/
  `status`/`logs`/`journal` service commands (dry-run aware), and the
  `boot/configure-node.sh` boot-config skeleton (env-render real; secret fetch
  + IMDS to follow in the Secrets work). Bats-tested.
- Milestone 6: SELinux — `lib/selinux.sh` + `kcadmin selinux apply`
  (`semanage fcontext` + `restorecon`, idempotent, dry-run aware) driven by a
  `semanage`-friendly `selinux/keycloak.fc`; applied automatically during
  `install`. Enforcing is never disabled (ADR-0011). Bats-tested.

## [0.1.0] - 2026-07-11
- Initial scaffold.
