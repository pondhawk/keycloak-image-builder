# KIB Architecture (pointer)

The authoritative architecture lives in two places:

1. **Blueprint** — `../Keycloak_Image_Builder_Architecture_Blueprint.md`
   (top-level specification).
2. **ADRs** — `../docs/adr/` (all decisions; win on specifics). Index:
   `../docs/adr/README.md`. All 12 Accepted.

## One-paragraph model

A **golden model instance** is provisioned by `kcimage` (Java 21 + Keycloak 26.x
+ toolkit), validated, sanitized by `seal`, and imaged into a **per-vendor
AMI**. An **Auto Scaling Group** launches ephemeral nodes from that AMI; each
node self-configures at boot (secrets from launch-template user-data → tmpfs, `keycloak.env`
from user-data), starts under systemd, joins the cluster via the built-in
`jdbc-ping` stack against a shared RDS (MySQL or Postgres), and serves HTTP behind
an ALB that terminates TLS. Upgrades are immutable (scale-to-0 cutover to a new
AMI); rollback is the previous AMI (+ RDS snapshot when schema migrated).

## Component map

- **`kcimage`** — Bash dispatcher + `lib/` helpers + `subcommands/`.
- **Install** — everything under `/opt/keycloak` (`KEYCLOAK_HOME`): one version, no versioned subdir, no `current` symlink.
- **Config** — neutral `keycloak.conf` baked at `/opt/keycloak/conf/`, read natively.
- **Custom providers** — staged in `~/keycloak-custom-providers/*.jar`, copied into `/opt/keycloak/providers` at build.
- **Runtime data** — `/opt/keycloak/data` (keycloak-owned; gzip cache, tx logs).
- **Boot-injected** — `/run/keycloak/{keycloak.env,secrets.env}` (tmpfs only, never on disk).
- **Units** — `keycloak-config.service` (root oneshot), `keycloak.service`.
- **Logging** — journald → (opt-in) Fluent Bit → CloudWatch.
