# ADR-0001: Directory Structure

- **Status:** Accepted
- **Date:** 2026-07-11
- **Deciders:** James Moring (owner), Claude Code (architect)
- **Format:** Nygard ADR (Context · Decision · Consequences)

## Context

The Keycloak Image Builder (KIB) builds an environment-neutral *golden
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

The upgrade model is immutable (new AMI + ASG instance refresh is canonical).
This is an **image-building node, never a production node**, so it never needs
two Keycloak versions installed side-by-side and never needs a `current`
pointer: it holds exactly one install at a time. (`upgrade` does move the old
install briefly aside to `/opt/keycloak.bak` while the new one builds, so a
failed upgrade rolls back — but that is transient, gone by the time the command
returns; see ADR-0006.) The layout should therefore keep everything
server-side in **one place** while keeping the operator's custom assets cleanly
separated from the install they get copied into.

## Decision

We adopt canonical, role-separated directory structures.

### 1. Source repository layout

Version-controlled under the project root (per blueprint §5):

```text
keycloak-image-builder/
├── .claude/                 # CLAUDE.md, coding-standards, architecture, project-rules
├── docs/
│   ├── adr/                 # this record and its siblings
│   ├── architecture/
│   ├── operations/
│   ├── troubleshooting/
│   └── images/
├── scripts/                 # kcimage and supporting scripts
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

Everything Keycloak-the-server lives under **one** tree, `/opt/keycloak`
(`KEYCLOAK_HOME`), in Keycloak's native layout. The only things outside it are
the operator's custom-asset staging dir (a different role) and the ephemeral
boot-injected config on tmpfs:

```text
# Java — canonical RPM location, installed via dnf, managed by alternatives
/usr/lib/jvm/<openjdk-21>

# Role A — the install: KEYCLOAK_HOME, one version, no versioned subdir, no `current`
/opt/keycloak/                 # root:root, immutable, usr_t
    bin/                       #   kc.sh (bin_t)
    lib/                       #   the augmented/optimized server
    conf/keycloak.conf         #   environment-neutral platform config, baked in, read natively
    providers/                 #   custom provider JARs land here at build time
    themes/
    data/                      #   keycloak-owned (0750), var_lib_t — gzip cache, tx logs

# Role B — custom provider JARs (source-controlled; staged, then copied into providers/ before build)
~/keycloak-custom-providers/   # operator-owned, in the invoking user's home
    *.jar                      # flat; themes ship as provider JARs too (best practice)

# Boot-injected, environment-specific config — tmpfs only, never on disk / in the image
/run/keycloak/                 # tmpfs, root:keycloak 0750 (ADR-0008)
    keycloak.env               #   non-secret runtime values (incl. JGroups bind addr)
    secrets.env                #   DB credentials, bootstrap admin
```

### Rules

- **Java** is a dnf-managed OpenJDK 21 under `/usr/lib/jvm`, selected via
  `alternatives`. KIB does not vendor a JDK under `/usr/java`.
- **Role A** (`/opt/keycloak/`) is `KEYCLOAK_HOME` — a single install, extracted
  straight here with **no versioned subdir and no `current` symlink** (this is an
  image-building node; it never keeps two versions). The install binaries are
  `root:root` and immutable (`usr_t`); the one exception is `data/` — Keycloak
  hardcodes its runtime data there (gzip cache, transaction logs) and must write
  it, so `install` creates it **keycloak-owned** (`0750`) and labelled `var_lib_t`
  (ADR-0011), and the service writes it in place (no relocation; the systemd unit
  runs without `ProtectSystem`, see ADR-0005). The neutral `conf/keycloak.conf`
  is baked in and read natively by `kc.sh` — no `KC_CONFIG_FILE` needed.
- **Role B** (`~/keycloak-custom-providers/`) holds operator-authored provider
  JARs (themes ship as JARs too). It lives in the invoking user's home — the
  same place the release tarball is downloaded and extracted — so it is
  operator-owned and populated by hand; `bootstrap.sh` creates it. It is never
  itself an installation, and it must be a **separate** tree from the install
  because `/opt/keycloak` does not exist until `install` creates it. Its `*.jar`
  contents are copied into `/opt/keycloak/providers` before `kc.sh build`.
  Override the location with `install`/`upgrade`/`verify --providers-dir`.
- **Boot-injected config** (`/run/keycloak/`) is tmpfs, written per boot by
  `keycloak-config.service` (ADR-0005/0008). **Both** `keycloak.env` (non-secret)
  and `secrets.env` land here, so nothing environment-specific ever touches the
  disk or the image. There are no `/var/lib`, `/var/log`, or `/var/backups`
  Keycloak trees and no `/etc/keycloak`: the neutral config is baked inside
  `KEYCLOAK_HOME`, runtime data lives in `KEYCLOAK_HOME/data`, and everything
  environment-specific is ephemeral on tmpfs.

## Consequences

### Positive

- Eliminates the `/opt/keycloak` name collision: the install and the operator's
  custom-provider staging dir are separate trees and can never be confused by a
  human, an upgrade step, a cleanup script, or `restorecon`.
- One tree to reason about. Everything server-side is under `KEYCLOAK_HOME`;
  there is no config in `/etc`, no state scattered across `/var`, and no
  versioned installs or `current` pointer to keep straight. `clean` removes one
  directory; `restorecon` relabels one tree.
- Canonical paths align with RHEL-family / RPM conventions (`/usr/lib/jvm`,
  `/opt`), and Keycloak's own native layout, so operator intuition mostly "just
  works."
- Custom assets survive a rebuild by construction — they live outside the
  install and are re-applied at build time.
- Nothing environment-specific ever lands on disk: the baked config is neutral,
  and per-boot env + secrets live only on tmpfs (`/run/keycloak`).

### Negative / Trade-offs

- Role B lives in a user home (`~/keycloak-custom-providers`) rather than a
  system path, so it inherits the home's ownership and default `user_home_t`
  label — no dedicated SELinux fcontext rule is needed (it is read at
  deploy-time only, before the JARs land in the labeled install tree).
- Role B holds a flat set of `*.jar` (custom provider JARs; themes ship as JARs
  too, per best practice). The earlier `providers/`, `themes/`, and `scripts/`
  subdirectories were dropped to keep a single, unambiguous deploy path.
- Collapsing to one install means an `upgrade` has no persistent previous
  version to fall back to; the safety margin is the transient `/opt/keycloak.bak`
  during the upgrade and, ultimately, the previous AMI (ADR-0006/0007). This is
  the right trade on a single-purpose build node.

### Notes

- Concrete ownership, permissions, and SELinux contexts for each tree are
  deferred to the Configuration, Secrets, and SELinux ADRs.
- The per-vendor AMI decision (build-time `--db`) does not change these paths;
  both the Postgres and MySQL AMIs share this identical layout.
