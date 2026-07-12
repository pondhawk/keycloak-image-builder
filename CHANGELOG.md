# Changelog

All notable changes to KDT are documented here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/); versioning is SemVer.

## [Unreleased]

### Removed
- Orphaned `templates/fluent-bit.conf`. Centralized logging (Fluent Bit →
  CloudWatch, ADR-0010) is deferred to a follow-up — `fluent-bit` is not in base
  RHEL repos and the packaging approach needs its own evaluation. On-node
  JSON→journald logging is unaffected.

### Changed
- **Scope consolidation:** `kcadmin` reduced to four model-instance commands —
  `install` (now also renders neutral config + runs `kc.sh build` + SELinux),
  `verify`, `ami-clean` (new; neutrality gate with `--check`), and `version`.
  Dropped the pets-oriented commands (`start`/`stop`/`restart`/`status`/`logs`/
  `journal`/`cluster`/`upgrade`/`rollback`/`health`) and folded `configure`/
  `build`/`check`/`selinux` into `install`/`verify`. Rationale: cattle/immutable
  model — nobody runs commands on production nodes; the toolkit builds a clean
  image. `boot/configure-node.sh` renders `keycloak.env` self-contained.

### Added
- `ami-clean` prunes non-`current` Keycloak installs under `/opt/keycloak` (keeps
  only the active version) — matters when the model instance is reused for OS
  patching, where old versions would otherwise accumulate into every AMI.
  `--opt-dir` override for testing.

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
- Milestone 7: Validation — `kcadmin build` (`kc.sh build`), `kcadmin health`
  (node-local `/health/live`+`/health/ready`), and `kcadmin verify` (pre-clean
  gate: Java, install, build, config, SELinux, units). Shared `lib/validate.sh`
  reporting (also refactored `check` onto it) + `join_sp` helper. Bats-tested.

## [0.1.0] - 2026-07-11
- Initial scaffold.
