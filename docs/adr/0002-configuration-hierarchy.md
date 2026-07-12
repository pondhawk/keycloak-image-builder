# ADR-0002: Configuration Hierarchy

- **Status:** Accepted
- **Date:** 2026-07-11
- **Deciders:** James Moring (owner), Claude Code (architect)
- **Format:** Nygard ADR (Context · Decision · Consequences)

## Context

KIB produces an environment-neutral golden AMI (per vendor) that an ASG
launches into many ephemeral, self-configuring nodes. Configuration therefore
has a hard constraint that ordinary Keycloak installs do not: **every value
must be classifiable as either baked-into-the-AMI (identical across all
environments) or injected-at-boot (environment-specific).** A value that is
both build-time *and* environment-specific cannot exist in a neutral AMI — the
only such value in Keycloak is the database vendor, which is why we bake one
AMI per vendor (ADR-0004).

Two independent classifications must be reconciled:

1. **Keycloak's build-time vs runtime option split.** `kc.sh build` bakes
   *build-time* options (e.g. `db` vendor, `features`, `health-enabled`,
   `metrics-enabled`, `cache`, `transaction-xa-enabled`) into an optimized
   server image. *Runtime* options (e.g. `db-url`, `db-username`,
   `db-password`, `hostname`, `http-*`, `proxy-headers`) are resolved at start.

2. **KIB's neutral vs environment-specific split.** Neutral values are safe to
   image and share across environments; environment-specific values are not and
   must come from outside the AMI (instance metadata,
   user-data).

The blueprint §7 already names three config artifacts — `keycloak.conf`,
`keycloak.env`, `bootstrap.env` — but does not define their precedence, their
delivery mechanism, or how secrets enter the picture. This ADR pins that.

Keycloak's own configuration sources resolve in descending precedence:
**CLI arguments → environment variables → configuration file → built-in
defaults** (a Java keystore config source also exists for sensitive values;
its exact placement is left to ADR-0008 Secrets). The critical, load-bearing
fact for KIB is that **environment variables override `keycloak.conf`** — this
is what lets boot-injected environment values override baked-in neutral config
without rebuilding.

## Decision

### Configuration layers (lowest to highest precedence)

| Layer | Source | Content | When set | In AMI? |
|-------|--------|---------|----------|---------|
| 0 | Keycloak built-in defaults | — | — | n/a |
| 1 | `/etc/keycloak/keycloak.conf` | **Build-time, environment-neutral** platform options | AMI bake | **Yes** |
| 2 | `/etc/keycloak/keycloak.env` (env vars) | **Runtime, environment-specific** values | First boot | No |
| 3 | Secrets (launch-template user-data) → env vars | **Sensitive** runtime values | First boot | No |
| 4 | CLI arguments (via `kcimage`) | Explicit operational overrides | On demand | n/a |

Higher layers override lower. This mirrors Keycloak's native precedence, so a
boot-injected env var (Layer 2/3) always wins over the baked `keycloak.conf`
(Layer 1).

### The classification rule

- **A build-time option MUST be environment-neutral** and live in
  `keycloak.conf` (Layer 1), baked into the AMI.
- **An environment-specific value MUST be a runtime option** and be injected at
  boot via `keycloak.env` / tmpfs `secrets.env` (Layers 2–3).
- **A value that is both build-time and environment-specific** cannot be
  neutralized; the only instance is `db` (vendor), resolved by per-vendor AMIs
  (ADR-0004). No other value may occupy this quadrant; the installer validates
  this.

### Artifact responsibilities

**`/etc/keycloak/keycloak.conf`** — build-time, neutral. Rendered from a repo
template at bake time. Examples: `db` (vendor only, no endpoint/credentials),
`cache`, `cache-stack`, `health-enabled`, `metrics-enabled`, `http-enabled`,
`proxy-headers` (`xforwarded` — TLS terminates at the ALB and nodes serve plain
HTTP, so there are no certs/keystores on instances), `transaction-xa-enabled`,
log format. Contains **no** endpoints, hostnames, or secrets. Consumed by
`kc.sh build`.

**`/etc/keycloak/keycloak.env`** — runtime, environment-specific, non-secret.
Rendered at first boot from instance metadata / user-data. Delivered to the
service as an `EnvironmentFile=` for the systemd unit (mechanism finalized in
ADR-0005). Examples: `KC_DB_URL` (RDS endpoint), `KC_DB_USERNAME`,
`KC_HOSTNAME`, `KC_HTTP_*`, and JVM sizing via `JAVA_OPTS_APPEND`.

**Secrets (launch-template user-data)** — runtime, sensitive. Retrieved at first boot
and delivered as environment variables (or via Keycloak's keystore config
source; decided in ADR-0008). Examples: `KC_DB_PASSWORD`, bootstrap admin
credentials. Never written into the AMI; never committed to the repo.

**`/etc/keycloak/bootstrap.env`** — transient. Holds temporary bootstrap admin
credentials (`KC_BOOTSTRAP_ADMIN_USERNAME` / `KC_BOOTSTRAP_ADMIN_PASSWORD`),
sourced from user-data on first boot only, used by the one-shot
initialization unit, and **removed after successful initialization**. Because
the RDS database is already populated (ADR scope), initialization is
idempotent: if the admin already exists, the boot logic skips creation and
still removes `bootstrap.env`.

### Pointing Keycloak at `/etc/keycloak`

Config lives in `/etc/keycloak`, outside the immutable install tree
(`/opt/keycloak/current`). Keycloak is directed there via `KC_CONFIG_FILE`
(or an equivalent `--config-file`) rather than by writing into the install's
`conf/`. The exact wiring is finalized in ADR-0005 (systemd); the requirement
here is only that **no configuration is stored inside the versioned install
directory**, preserving install immutability.

### Validation

At bake and at boot, `kcimage` verifies:

- `keycloak.conf` contains no environment-specific values (neutrality gate,
  paired with `seal`).
- All required runtime env (DB URL/username/password, hostname) is present
  before the service is allowed to start.
- `bootstrap.env`, if present, is removed once initialization succeeds.

## Consequences

### Positive

- A single, testable rule ("neutral+build-time → baked; env-specific → boot")
  makes AMI neutrality auditable rather than a matter of discipline.
- Boot-injected env vars overriding baked `keycloak.conf` is exactly Keycloak's
  native precedence, so KIB fights the tool less.
- Secrets never touch the AMI or the repo; they have a single delivery path
  (user-data → env at boot), simplifying the Secrets ADR.
- Keeping config out of `/opt/keycloak/current` preserves the immutability that
  the upgrade model (ADR-0006) depends on.

### Negative / Trade-offs

- Contributors must learn Keycloak's build-time/runtime option split to know
  which file a new option belongs in; a misplaced option either breaks AMI
  neutrality or silently fails to take effect. The neutrality gate catches the
  first case but not the second — documentation and templates must be explicit.
- The boot script parses user-data and routes secrets to tmpfs — a small added
  moving part to first-boot orchestration.
- The `db` vendor being the sole build-time/env-specific value is a constraint
  that must be actively defended: any future option with the same character
  would force additional AMI variants.

### Notes

- Exact secret-delivery mechanism (env vars vs Keycloak keystore config source)
  → ADR-0008.
- `EnvironmentFile` wiring and unit ordering → ADR-0005.
- Per-vendor AMI mechanics → ADR-0004.
