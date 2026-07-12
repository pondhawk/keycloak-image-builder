# Changelog

All notable changes to KIB are documented here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/); versioning is SemVer.

## [Unreleased]

### Removed
- Orphaned `templates/fluent-bit.conf`. Centralized logging (Fluent Bit →
  CloudWatch, ADR-0010) is deferred to a follow-up — `fluent-bit` is not in base
  RHEL repos and the packaging approach needs its own evaluation. On-node
  JSON→journald logging is unaffected.

### Changed
- **README is now a runbook hub.** Rewrote it around Description · Requirements ·
  Install the toolkit · a Runbooks menu, with self-contained, copy-paste runbooks
  in `docs/runbooks/` (`fresh-install`, `upgrade-install`, `os-patch`,
  `clean-install`, `deploy-aws`). Every model-instance runbook ends at "ready for
  image"; `deploy-aws` carries the AWS-side story (AMI, launch-template `KC_*`
  user-data, rolling vs scale-to-0 rollout). Requirements corrected: OS floor is
  **RHEL-family 9+** (really `dnf` + SELinux Enforcing + systemd + `java-21`), and
  the DB is **any reachable Postgres/MySQL**, not specifically RDS.
- **Dropped AWS Secrets Manager** for boot config — the node now reads config (incl. DB creds) from launch-template user-data (KEY=VALUE, KC_* names) + private IP from IMDS, split into keycloak.env + tmpfs secrets.env. No AWS CLI, no jq, no VPC endpoint / secrets IAM. ADR-0008 revised with the threat-model rationale.
- **Scope consolidation:** `kcimage` reduced to four core model-instance
  commands — `install` (now also renders neutral config + runs `kc.sh build` +
  SELinux), `verify`, `seal` (new; neutrality gate with `--check`), and
  `version` (plus `clean`, below, for testing).
  Dropped the pets-oriented commands (`start`/`stop`/`restart`/`status`/`logs`/
  `journal`/`cluster`/`upgrade`/`rollback`/`health`) and folded `configure`/
  `build`/`check`/`selinux` into `install`/`verify`. Rationale: cattle/immutable
  model — nobody runs commands on production nodes; the toolkit builds a clean
  image. `boot/configure-node.sh` renders `keycloak.env` self-contained.

### Added
- `install` now **deploys custom provider JARs** from
  `~/keycloak-custom-providers` (flat `*.jar`) into the active install before
  `kc.sh build` (ADR-0001, blueprint §8) — previously it only created the
  directory. Themes ship as provider JARs (best practice), so only providers is
  supported. Assets carry across Keycloak upgrades; README documents the
  workflow. Override the location with `--providers-dir`. `verify` now
  confirms **every** custom provider JAR landed in the install (FAILs, listing
  any that didn't).
- `clean` command — inverts `install`, returning the model instance to a
  pristine, ready-to-install state (removes Keycloak, config, state, units, boot
  script, service user, SELinux rules). Keeps the toolkit, OpenJDK (unless
  `--purge-java`), and `~/keycloak-custom-providers`. Idempotent (reports
  `already clean`), dry-run aware, requires `--yes` for a real run. Mostly for
  testing; confirm a torn-down state with `kcimage --dry-run clean`.
- Boot node configuration implemented in `boot/configure-node.sh`: IMDSv2 (token
  + private IP) + launch-template user-data (KEY=VALUE, KC_* names), split into
  `keycloak.env` (non-secret) and tmpfs `secrets.env` (0640; DB credentials +
  optional bootstrap admin). No AWS CLI / jq. Never logs secrets; env-override
  hooks make the split Bats-testable without IMDS.
- `seal` prunes non-`current` Keycloak installs under `/opt/keycloak` (keeps
  only the active version) — matters when the model instance is reused for OS
  patching, where old versions would otherwise accumulate into every AMI.
  `--opt-dir` override for testing.

- Milestone 1: all 12 Architecture Decision Records (`docs/adr/`), Accepted.
- Type B rollback runbook (`docs/operations/rollback-with-db-restore.md`).
- Milestone 2: repository scaffolding — `kcimage` dispatcher, `lib/` helpers,
  systemd units, config templates, SELinux fcontext, Bats test, Makefile,
  GitHub Actions (CI + release), `.claude/` standards.
- Milestone 3: `kcimage install` — ensures OpenJDK, the service user, the
  directory tree (ADR-0001), and a side-by-side Keycloak distribution with
  `current` symlink management. Idempotent, dry-run aware; Bats-tested.
- Milestone 3: `kcimage check` — read-only host prerequisite validation
  (Java, systemd, SELinux Enforcing, DNS, commands, optional RDS TCP; §12).
- Milestone 4: `kcimage configure` — render `keycloak.conf` (neutral, vendor
  substituted) and `keycloak.env` (from the environment via `envsubst`) into
  `/etc/keycloak`, with an ADR-0002 neutrality guard. `--etc-dir` override,
  dry-run aware; Bats-tested.
- Milestone 5: systemd integration — `lib/systemd.sh` + `start`/`stop`/`restart`/
  `status`/`logs`/`journal` service commands (dry-run aware), and the
  `boot/configure-node.sh` boot-config skeleton (env-render real; secret fetch
  + IMDS to follow in the Secrets work). Bats-tested.
- Milestone 6: SELinux — `lib/selinux.sh` + `kcimage selinux apply`
  (`semanage fcontext` + `restorecon`, idempotent, dry-run aware) driven by a
  `semanage`-friendly `selinux/keycloak.fc`; applied automatically during
  `install`. Enforcing is never disabled (ADR-0011). Bats-tested.
- Milestone 7: Validation — `kcimage build` (`kc.sh build`), `kcimage health`
  (node-local `/health/live`+`/health/ready`), and `kcimage verify` (pre-clean
  gate: Java, install, build, config, SELinux, units). Shared `lib/validate.sh`
  reporting (also refactored `check` onto it) + `join_sp` helper. Bats-tested.

## [0.1.0] - 2026-07-11
- Initial scaffold.
