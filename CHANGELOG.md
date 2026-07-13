# Changelog

All notable changes to KIB are documented here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/); versioning is SemVer.

## [Unreleased]

### Removed
- Orphaned `templates/fluent-bit.conf`. Centralized logging (Fluent Bit →
  CloudWatch, ADR-0010) is deferred to a follow-up — `fluent-bit` is not in base
  RHEL repos and the packaging approach needs its own evaluation. On-node
  JSON→journald logging is unaffected.

### Fixed
- **Admin console now loads in a browser.** Keycloak caches gzip-encoded
  admin-console assets under `KEYCLOAK_HOME/data/tmp/kc-gzip-cache`, but the
  install tree is `root:root` and read-only at runtime (`ProtectSystem=strict`),
  so the cache write failed and every browser (all send `Accept-Encoding: gzip`)
  got a **404** on the CSS/JS — the console wouldn't load (keycloak/keycloak#31949,
  closed "not planned"). Two parts, both required:
  (1) `install` symlinks `/opt/keycloak/<ver>/data -> /var/lib/keycloak/data`
  (keycloak-writable, in the unit's `ReadWritePaths`); and
  (2) `keycloak.service` gets `StateDirectory=keycloak/data`, so systemd recreates
  that target dir keycloak-owned on **every start** — the symlink alone dangled
  because `seal` purges `/var/lib/keycloak`, and Java's `createDirectories` throws
  on a dangling symlink. `verify` also checks the service user can write `data/`,
  so it fails on the model, not at node boot. Diagnosed and validated live on a
  real node (`GzipResourceEncodingProviderFactory: Failed to create gzip cache
  directory …/data/tmp/kc-gzip-cache`). (An earlier attempt via
  `quarkus.http.enable-compression` was the wrong layer and was dropped.)
- **`seal` neutrality gate no longer false-positives on comments** (found on the
  first real-instance `seal`). The gate scanned all of `/etc/keycloak` including
  comment lines, so the neutral `keycloak.conf` header ("…no endpoints,
  hostnames, or secrets") matched `secret` and failed the gate. It now strips
  comment/blank lines before scanning (matching the install-time neutrality
  check) and also flags `://` endpoints. The Bats "gate passes" test now embeds a
  `secrets` comment so this can't regress.

### Changed
- **Mutating commands refuse on a running node.** `install`/`upgrade`/`seal`/
  `clean` check `keycloak.service`; if it's active — a live ASG node, never the
  model instance (which builds/seals but never starts Keycloak) — they refuse.
  Belt-and-suspenders beyond the confirmation prompt, so the toolkit baked into
  the image can't wreck a production node even if someone confirms. Escape hatch
  is `systemctl stop keycloak` (never needed on a real model); no bypass flag.
- **`bootstrap.sh` symlinks `/usr/sbin/kcimage`** so `sudo kcimage` works on
  hardened images whose sudo `secure_path` excludes `/usr/local/bin` (found
  during real-instance testing — `sudo kcimage` gave "command not found"). Uses
  `/usr/sbin` (in every default `secure_path`); no sudoers edit, no override of a
  deliberate hardening choice.
- **`install`/`upgrade` now hard-refuse Keycloak majors below 26** (was a
  warning). The baked config is 26-era — jdbc-ping cache stack,
  `KC_BOOTSTRAP_ADMIN_*`, management port — and those are mostly *runtime*
  options, so an older version would pass `install`/`verify`/`seal` on the model
  and only fail at node boot in the ASG. Refusing on the model moves that failure
  to one line, early. Newer majors still proceed with a warning.
- **Mutating commands now prompt for confirmation; `clean --yes` is gone.** All
  four state-changing commands (`install`, `upgrade`, `seal`, `clean`) ask for an
  interactive `y/N` before doing anything, and there is **no `--yes`/`--force`
  bypass** — by design. A bypass flag baked into shell history defeats the prompt
  on an accidental up-arrow re-run (the exact scenario the prompt exists to stop).
  `--dry-run` skips the prompt (nothing happens); with no terminal the command
  refuses rather than proceed unattended. `clean`'s old `--yes` requirement is
  removed. Shared helper: `confirm()` in `lib/common.sh`.
- **Split `install` into `install` + `upgrade`; both activate by default.**
  `install` is now **greenfield-only** — it establishes a fresh lineage, requires
  `--db-vendor`, and refuses if the model already has an install (pointing you to
  `upgrade` or `clean`). The new **`upgrade`** command moves an existing install
  to a new Keycloak version and **reads the DB vendor from the model** (no
  `--db-vendor`), so an upgrade structurally *cannot* change the image's baked
  vendor — closing a footgun where `install --db-vendor <wrong>` on an existing
  lineage would silently mis-build the image and only fail at boot. Both commands
  point `/opt/keycloak/current` at the version automatically (the old opt-in
  `--activate` is gone). `install` and `upgrade` share one internal pipeline
  (`_install_core`).
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
  `already clean`), dry-run aware, prompts for confirmation before removing
  anything. Mostly for testing; confirm a torn-down state with
  `kcimage --dry-run clean`.
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
