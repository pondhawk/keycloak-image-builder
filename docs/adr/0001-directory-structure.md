# ADR-0001: Directory Structure

- **Status:** Accepted
- **Date:** 2026-07-11
- **Deciders:** James Moring (owner), Claude Code (architect)
- **Format:** Nygard ADR (Context · Decision · Consequences)

## Context

The Keycloak Deployment Toolkit (KDT) builds an environment-neutral *golden
model instance* that is imaged into an AMI and consumed by an AWS Auto
Scaling Group (ASG). Two distinct directory structures must be pinned before
any code is written, because nearly every later ADR (configuration, AMI/build,
upgrade, SELinux) references paths:

1. **The source repository** — what lives in version control.
2. **The runtime filesystem** — what exists on a provisioned instance and,
   after sanitization, inside the AMI.

The blueprint's original §6 filesystem layout had two problems we must resolve
here:

- Keycloak was placed under `/usr/java/`, a path conventionally reserved for
  JDKs, not applications.
- `/opt/keycloak/` was overloaded for **two different roles** whose
  subdirectories collide by name (`themes/`, `providers/`):
  - the actual Keycloak installation (which already contains its own
    `themes/` and `providers/` directories), and
  - the operator's custom, source-controlled theme/provider assets that are
    copied *into* an installation before `kc.sh build`.

  This ambiguity risks an upgrade, cleanup script, or SELinux `restorecon`
  operating on the wrong tree.

The upgrade model is immutable (new AMI + ASG instance refresh is canonical);
the side-by-side install + `current` symlink swap is used **only on the golden
instance** to prepare and validate a version before baking. The layout must
support that side-by-side pattern on the golden instance while keeping the
three runtime roles cleanly separated.

## Decision

We adopt canonical, role-separated directory structures.

### 1. Source repository layout

Version-controlled under the project root (per blueprint §5):

```text
keycloak-admin-tool/
├── .claude/                 # CLAUDE.md, coding-standards, architecture, project-rules
├── docs/
│   ├── adr/                 # this record and its siblings
│   ├── architecture/
│   ├── operations/
│   ├── troubleshooting/
│   └── images/
├── scripts/                 # kcadmin and supporting scripts
├── systemd/                 # unit + drop-in templates
├── selinux/                 # policy modules / fcontext definitions
├── templates/               # keycloak.conf / keycloak.env / bootstrap.env templates
├── tests/                   # Bats suites
├── examples/
├── Makefile
├── README.md
├── CHANGELOG.md
└── ROADMAP.md
```

### 2. Runtime filesystem layout

Three roles, each in its own tree so none can be mistaken for another:

```text
# Java — canonical RPM location, installed via dnf, managed by alternatives
/usr/lib/jvm/<openjdk-21>

# Role A — installations (immutable, versioned; symlink swap only on golden instance)
/opt/keycloak/
    keycloak-<version>/
    current -> keycloak-<version>

# Role B — custom provider JARs (source-controlled; deployed into current/ before build)
/opt/keycloak-custom/
    providers/     # themes ship as provider JARs too (best practice)

# Config
/etc/keycloak/
    keycloak.conf         # environment-neutral platform config (build-time options)
    keycloak.env          # environment-specific values (runtime options)
    bootstrap.env         # temporary admin credentials; removed after init

# Role C — runtime state
/var/lib/keycloak/
/var/log/keycloak/
/var/backups/keycloak/
```

### Rules

- **Java** is a dnf-managed OpenJDK 21 under `/usr/lib/jvm`, selected via
  `alternatives`. KDT does not vendor a JDK under `/usr/java`.
- **Role A** (`/opt/keycloak/`) holds only Keycloak installations and the
  `current` symlink. The `current` symlink is the single mutable pointer, and
  it is swapped **only on the golden instance** during version preparation.
- **Role B** (`/opt/keycloak-custom/`) holds operator-authored themes,
  providers, and scripts. It is never itself an installation. Its contents are
  copied into `/opt/keycloak/current` before `kc.sh build`.
- **Role C** (`/var/lib`, `/var/log`, `/var/backups`) holds mutable runtime
  state and is excluded from the AMI's environment-neutral guarantee (sanitized
  by `kcadmin ami-clean`).
- **Config** lives in `/etc/keycloak`. `keycloak.conf` carries build-time /
  platform-neutral options (baked into the AMI); `keycloak.env` carries
  runtime / environment-specific values (injected at boot). `bootstrap.env` is
  transient.

## Consequences

### Positive

- Eliminates the `/opt/keycloak` name collision: Role A and Role B can never be
  confused by a human, an upgrade step, a cleanup script, or `restorecon`.
- Canonical paths align with RHEL-family / RPM conventions (`/usr/lib/jvm`,
  `/opt`, `/etc`, `/var`), so SELinux fcontext defaults and operator intuition
  mostly "just work."
- Custom assets survive upgrades by construction — they live outside every
  installation and are re-applied at build time.
- The `current`-symlink pattern gives the golden instance safe side-by-side
  version prep with a trivial, atomic switch and an obvious rollback.
- A single mutable pointer (`current`) keeps immutable installations immutable.

### Negative / Trade-offs

- Introduces a new top-level path (`/opt/keycloak-custom`) that must be created,
  owned, and SELinux-labeled by the installer (addressed in the SELinux ADR).
- `/opt/keycloak-custom` holds only `providers/` (custom provider JARs; themes
  ship as JARs too, per best practice). The earlier `themes/` and `scripts/`
  subdirectories were dropped to keep a single, unambiguous deploy path.
- The `current` symlink is meaningful only on the golden instance; on ASG
  nodes it is effectively frozen at bake time. Operators must understand that
  swapping it on a live production node is not the supported upgrade path
  (see the Upgrade ADR).

### Notes

- Concrete ownership, permissions, and SELinux contexts for each tree are
  deferred to the Configuration, Secrets, and SELinux ADRs.
- The per-vendor AMI decision (build-time `--db`) does not change these paths;
  both the Postgres and MySQL AMIs share this identical layout.
