# Keycloak Image Builder (KIB)

`kcimage` — a Bash CLI that turns a fresh **RHEL-family 10** instance into a
**golden Keycloak model**, then sanitizes it so you can bake an environment-neutral
AMI. That AMI is what your Auto Scaling Group launches.

> **Status:** v0.1.0 — the four commands work and CI is green; real-instance
> testing and the boot secret-fetch remain. See `ROADMAP.md`.

KIB is a **model-instance build tool**, not a production-node console (nodes are
cattle). It does exactly three things on the model instance:

**install/update → verify → prepare-for-image.**

---

## Requirements

- **RHEL-family 10** (Rocky / AlmaLinux / RHEL) — needs `dnf` and **SELinux Enforcing**
- **root** on the model instance (`sudo`)
- Internet access to download the Keycloak distribution
- An existing, populated **RDS** (PostgreSQL or MySQL) for the running cluster
  (KIB never creates databases)

---

## Install the toolkit

Download the latest release, extract it, and run `bootstrap.sh` to put `kcimage`
on your `PATH`. (`kcimage install` later bakes everything the *AMI* needs;
`make` is not required on the model instance.)

Download, extract, and install (the version is resolved automatically):

```bash
KIB_VERSION=$(curl -fsSL https://api.github.com/repos/pondhawk/keycloak-image-builder/releases/latest \
  | sed -n 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/p')
curl -fsSL -o kcimage.tar.gz \
  "https://github.com/pondhawk/keycloak-image-builder/releases/download/v${KIB_VERSION}/kcimage-${KIB_VERSION}.tar.gz"
tar xzf kcimage.tar.gz
cd "kcimage-${KIB_VERSION}"
sudo ./bootstrap.sh          # installs kcimage to /usr/local/bin
```

Confirm it's on your `PATH`:

```bash
kcimage version
```

To upgrade the toolkit later, download a newer release and run `sudo ./bootstrap.sh`
again — it overwrites in place, so `kcimage` always points at the latest (no
versioned path ever lands in your shell history).

---

## Build a golden AMI (the whole workflow)

With `kcimage` on your `PATH`, run (as root):

```bash
# 1. Install/update Keycloak and bake the model (Java, distribution, config,
#    build, systemd units + boot script, SELinux)
sudo kcimage install --keycloak-version 26.1.4 --db-vendor mysql

# 2. Validate the install
sudo kcimage verify

# 3. Sanitize for imaging (removes secrets/identity, runs the neutrality gate)
sudo kcimage seal

# 4. Create the AMI in the AWS Console:
#    EC2 → the model instance → Actions → Image and templates → Create image
```

Preview any step without changing anything using `--dry-run`:

```bash
kcimage --dry-run install --keycloak-version 26.1.4 --db-vendor postgres
```

---

## Commands

### `install` — install/update Keycloak on the model

```bash
# Fresh install (mysql-flavoured AMI)
sudo kcimage install --keycloak-version 26.1.4 --db-vendor mysql

# Postgres-flavoured AMI, and activate this version's symlink
sudo kcimage install --keycloak-version 26.1.4 --db-vendor postgres --activate

# Update: install a newer version side-by-side (repeat verify/seal, bake a new AMI)
sudo kcimage install --keycloak-version 26.2.0 --db-vendor mysql --activate
```

| Option | Meaning |
|--------|---------|
| `--keycloak-version <v>` | Keycloak version to install (required), e.g. `26.1.4` |
| `--db-vendor <v>` | `postgres` or `mysql` (required; baked into the AMI) |
| `--java-package <pkg>` | OpenJDK package (default `java-21-openjdk-headless`) |
| `--activate` | Point `/opt/keycloak/current` at this version |

### `verify` — validate the install

```bash
sudo kcimage verify
```

Checks Java, the install, `kc.sh build`, rendered config, SELinux Enforcing, and
the systemd units. Exits non-zero if any check fails.

### `seal` — prepare for imaging

```bash
# Sanitize this instance and run the neutrality gate
sudo kcimage seal

# Run ONLY the neutrality gate (no changes) — e.g. to re-confirm before imaging
kcimage seal --check
```

Removes secrets, environment-specific config, runtime state, and machine
identity, then **fails** if anything sensitive remains.

### `version` — show versions

```bash
kcimage version
```

---

## Custom providers

Custom Keycloak **providers** are source-controlled separately and baked into
the build. Put your provider JARs on the model instance under
`/opt/keycloak-custom/providers` **before** running `install` — it copies them
into the active install and `kc.sh build` bakes them in. (Custom **themes** are
packaged as provider JARs too — best practice — so they go here as well.)

```text
/opt/keycloak-custom/
└── providers/    # your provider JARs (themes packaged as JARs go here too)
```

Example:

```bash
sudo mkdir -p /opt/keycloak-custom/providers
sudo cp my-provider.jar /opt/keycloak-custom/providers/

sudo kcimage install --keycloak-version 26.1.4 --db-vendor mysql
```

Because the assets live outside the versioned install, `install` re-deploys and
re-builds them on every install/update — so they **carry across Keycloak
upgrades** automatically.

---

## Global flags

```bash
kcimage --dry-run <command>   # show planned actions, change nothing
kcimage --verbose <command>   # debug-level logging
kcimage --help                # usage
```

---

## Development

```bash
make check     # ShellCheck + shfmt
make test      # Bats
make package   # build the release tarball (kcimage-<version>.tar.gz)
```

---

## Documentation

- **Blueprint:** `Keycloak_Image_Builder_Architecture_Blueprint.md`
- **Decisions (ADRs):** `docs/adr/` (`docs/adr/README.md`)
- **Runbooks:** `docs/operations/`
- **Contributor guidance:** `.claude/`
