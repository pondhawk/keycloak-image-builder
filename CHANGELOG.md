# Changelog

All notable changes to KIB are documented here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/); versioning is SemVer.

## [Unreleased]

### Changed
- **Baked log level defaults to `warn`.** `keycloak.conf` now sets
  `log-level=warn` (production-lean) instead of Keycloak's `info` default. It's
  overridable per-node at boot with `KC_LOG_LEVEL` in launch-template user-data
  (env wins over `keycloak.conf`; `log-level` is a runtime option, so no
  rebuild) — e.g. `KC_LOG_LEVEL=info` to debug a node, or
  `KC_LOG_LEVEL=warn,org.keycloak:info` per-category. Documented in the
  deploy-aws runbook's user-data table.

## [2.2.0] — 2026-07-13

### Added
- **ARM64 / aarch64 support.** KIB runs on both x86_64 and ARM64 hosts —
  Keycloak's distribution is architecture-independent and OpenJDK is dnf-resolved
  per host, so an image's arch is simply the arch of the model you build on.
  `install` takes an optional `--arch x64|arm64` that asserts the host matches and
  refuses on mismatch — KIB can't cross-build. `verify` reports the
  architecture as a check and `version` prints it; the deploy runbook gains an
  `arch` AMI tag and Graviton instance-type guidance.

## [2.1.1] — 2026-07-13

### Fixed
- **`seal` neutrality gate no longer false-positives on Keycloak's stock config
  files.** With config now in Keycloak's native `/opt/keycloak/conf`, that
  directory ships stock files (`cache-ispn.xml`, `README.md`) containing `://`
  URIs and doc links; the gate scanned the whole directory and failed on them. It
  now scans only the one file KIB renders (`keycloak.conf`), and fails closed if
  that file is missing.

### Added
- **Version banner.** `install`/`upgrade`/`verify`/`seal`/`clean` print a
  `=== kcimage <version> ===` line on stderr, so a stale toolkit — e.g. a
  forgotten `bootstrap.sh` after a release — is obvious at a glance. `version` is
  excluded (it prints the version itself). Each model-instance runbook now also
  opens with a `kcimage version` check.

### Changed
- CI/release GitHub Actions moved off the deprecated Node 20 runtime and pinned
  to commit SHAs (`actions/checkout` v5.0.1, `softprops/action-gh-release`
  v3.0.1) so a repointed tag can't inject into CI or the release job.

## [2.1.0] — 2026-07-13

### Added
- **Supply-chain: `install` GPG-verifies the Keycloak distribution** before
  extracting it into the image (ADR-0004). The downloaded tarball's signature is
  checked against Keycloak's pinned release-signing key (fingerprint
  `861AB50E8CC6611FB6BC01A6B8F12EA26FD6EEBA`, "Keycloak Bot", published at
  <https://www.keycloak.org/keys>); the public key is committed at
  `templates/keycloak-release-key.asc`, sourced from that page, so verification
  needs no keyserver. Fail-closed — no valid signature, no install. `gpg` is now
  a required command on the model.

### Security
- **`seal` scrubs cloud-init state + operator shell history.** cloud-init caches
  the raw launch-template user-data — which carries `KC_DB_PASSWORD` — in
  cleartext under `/var/lib/cloud`, and echoes it into its logs; both would bake
  into the image. `seal` now runs `cloud-init clean --logs --seed`, removes the
  cached user-data and cloud-init logs, and clears **both** root's and the
  sudo-invoking operator's `~/.bash_history`.
- **The Keycloak distribution is signature-verified** (see Added) — closes the
  gap where an MITM'd or mutated release asset could be baked into the auth image.

### Removed
- Orphaned `templates/fluent-bit.conf`. Centralized logging (Fluent Bit →
  CloudWatch, ADR-0010) is deferred to a follow-up — `fluent-bit` is not in base
  RHEL repos and the packaging approach needs its own evaluation. On-node
  JSON→journald logging is unaffected.

### Fixed
- **Permission hardening in `install`** (from an adversarial permission audit):
  guarantee `o+x` on the `/opt/keycloak` top dir — the `keycloak` user reaches
  `conf/` and `data/` as "other", so a non-traversable top dir would silently
  break config reads and the gzip cache (keycloak#31949) — and re-assert
  `keycloak:keycloak` ownership of `data/` after `kc.sh build` (which runs as root
  and can leave root-owned entries there).
- **Admin console now loads in a browser** — Keycloak's `KEYCLOAK_HOME/data` is
  writable by the service user, in place. Keycloak writes runtime data under its
  home (the gzip resource cache at `data/tmp/kc-gzip-cache`, transaction logs,
  …), but the install tree was `root:root` + read-only at runtime
  (`ProtectSystem=strict`), so those writes failed — most visibly, every browser
  (all send `Accept-Encoding: gzip`) got a **404** on the admin-console CSS/JS and
  the console wouldn't load (keycloak/keycloak#31949, closed "not planned").
  Fixed by letting Keycloak do the normal thing: `install` creates
  `/opt/keycloak/<ver>/data` owned by `keycloak`, SELinux labels it `var_lib_t`
  (writable-state), and `keycloak.service` **drops `ProtectSystem=strict`** (it
  runs unprivileged and owns its data). This removed the read-only-tree hardening
  that was fighting Keycloak, and with it the symlink, `StateDirectory`, and
  `/var/lib/keycloak/data` machinery from earlier attempts. `verify` checks the
  service user can write `data/`, so it fails on the model, not at node boot.
- **`seal` neutrality gate no longer false-positives on comments** (found on the
  first real-instance `seal`). The gate scanned all of `/etc/keycloak` including
  comment lines, so the neutral `keycloak.conf` header ("…no endpoints,
  hostnames, or secrets") matched `secret` and failed the gate. It now strips
  comment/blank lines before scanning (matching the install-time neutrality
  check) and also flags `://` endpoints. The Bats "gate passes" test now embeds a
  `secrets` comment so this can't regress.

### Changed
- **Consolidated the entire server-side layout under `/opt/keycloak`**
  (ADR-0001). Keycloak installs to its native layout (`bin/ lib/ conf/keycloak.conf
  data/ providers/ themes/`) as a **single version — no versioned subdir, no
  `current` symlink** (this is an image-building node, never production; no
  side-by-side). Dropped `/etc/keycloak` and `/var/lib|log|backups/keycloak`
  entirely; the only thing outside `/opt/keycloak` is boot-injected env + secrets
  on tmpfs `/run/keycloak`. `keycloak.conf` is baked in `conf/` and read natively
  (no `KC_CONFIG_FILE`); `keycloak.env` now lands on tmpfs alongside secrets, so
  nothing environment-specific ever touches disk (ADR-0002/0008).
- **`upgrade` is now a safe in-place swap** (ADR-0006). It reads the DB vendor
  from the existing `keycloak.conf` (so an upgrade can't change the baked vendor),
  moves the current install aside, installs the new version, and removes the old
  **only after** the new one builds — rolling back to the previous install on
  failure. No persistent side-by-side. Changing DB vendor is `clean` + `install`.
- **Test-only path overrides are env-var hooks, not flags.** `--etc-dir`,
  `--conf-dir`, `--home`, `--opt-dir`, and `--systemd-dir` are gone from the
  commands; the Bats suite uses `KIB_CONF_DIR`/`KIB_HOME`/`KIB_SYSTEMD_DIR`/
  `KIB_RUN` instead. `--providers-dir` remains (a real operator option).
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
