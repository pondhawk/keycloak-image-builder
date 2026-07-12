# Keycloak Deployment Toolkit (KDT)

`kcadmin` — a Bash CLI that turns a fresh **RHEL-family 10** instance into a
**golden Keycloak model**, then sanitizes it so you can bake an environment-neutral
AMI. That AMI is what your Auto Scaling Group launches.

> **Status:** v0.1.0 — the four commands work and CI is green; real-instance
> testing and the boot secret-fetch remain. See `ROADMAP.md`.

KDT is a **model-instance build tool**, not a production-node console (nodes are
cattle). It does exactly three things on the model instance:

**install/update → verify → prepare-for-image.**

---

## Requirements

- **RHEL-family 10** (Rocky / AlmaLinux / RHEL) — needs `dnf` and **SELinux Enforcing**
- **root** on the model instance (`sudo`)
- Internet access to download the Keycloak distribution
- An existing, populated **RDS** (PostgreSQL or MySQL) for the running cluster
  (KDT never creates databases)

---

## Get the toolkit onto the model instance

There is **no install step** — you run `kcadmin` straight from the extracted
tarball. `kcadmin install` itself bakes everything the AMI needs (Keycloak,
config, build, systemd units, boot script, SELinux). `make` is **not** required
on the model instance.

Download and extract a published release:

```bash
KDT_VERSION=0.1.0
curl -fsSL -o kcadmin.tar.gz \
  "https://github.com/pondhawk/keycloak-admin-tool/releases/download/v${KDT_VERSION}/kcadmin-${KDT_VERSION}.tar.gz"
tar xzf kcadmin.tar.gz
cd "kcadmin-${KDT_VERSION}"
```

Confirm it runs:

```bash
./scripts/kcadmin version
```

---

## Build a golden AMI (the whole workflow)

From the extracted directory:

```bash
# 1. Install/update Keycloak and bake the model (Java, distribution, config,
#    build, systemd units + boot script, SELinux)
sudo ./scripts/kcadmin install --keycloak-version 26.1.4 --db-vendor mysql

# 2. Validate the install
sudo ./scripts/kcadmin verify

# 3. Sanitize for imaging (removes secrets/identity, runs the neutrality gate)
sudo ./scripts/kcadmin ami-clean

# 4. Create the AMI in the AWS Console:
#    EC2 → the model instance → Actions → Image and templates → Create image
```

Preview any step without changing anything using `--dry-run`:

```bash
./scripts/kcadmin --dry-run install --keycloak-version 26.1.4 --db-vendor postgres
```

(Examples below write `kcadmin` for brevity; run it as `./scripts/kcadmin` from
the extracted directory, or add it to your `PATH`.)

---

## Commands

### `install` — install/update Keycloak on the model

```bash
# Fresh install (mysql-flavoured AMI)
sudo kcadmin install --keycloak-version 26.1.4 --db-vendor mysql

# Postgres-flavoured AMI, and activate this version's symlink
sudo kcadmin install --keycloak-version 26.1.4 --db-vendor postgres --activate

# Update: install a newer version side-by-side (repeat verify/ami-clean, bake a new AMI)
sudo kcadmin install --keycloak-version 26.2.0 --db-vendor mysql --activate
```

| Option | Meaning |
|--------|---------|
| `--keycloak-version <v>` | Keycloak version to install (required), e.g. `26.1.4` |
| `--db-vendor <v>` | `postgres` or `mysql` (required; baked into the AMI) |
| `--java-package <pkg>` | OpenJDK package (default `java-21-openjdk-headless`) |
| `--activate` | Point `/opt/keycloak/current` at this version |

### `verify` — validate the install

```bash
sudo kcadmin verify
```

Checks Java, the install, `kc.sh build`, rendered config, SELinux Enforcing, and
the systemd units. Exits non-zero if any check fails.

### `ami-clean` — prepare for imaging

```bash
# Sanitize this instance and run the neutrality gate
sudo kcadmin ami-clean

# Run ONLY the neutrality gate (no changes) — e.g. to re-confirm before imaging
kcadmin ami-clean --check
```

Removes secrets, environment-specific config, runtime state, and machine
identity, then **fails** if anything sensitive remains.

### `version` — show versions

```bash
kcadmin version
```

---

## Global flags

```bash
kcadmin --dry-run <command>   # show planned actions, change nothing
kcadmin --verbose <command>   # debug-level logging
kcadmin --help                # usage
```

---

## Development

```bash
make check     # ShellCheck + shfmt
make test      # Bats
make package   # build the release tarball (kcadmin-<version>.tar.gz)
```

---

## Documentation

- **Blueprint:** `Keycloak_Deployment_Toolkit_Architecture_Blueprint.md`
- **Decisions (ADRs):** `docs/adr/` (`docs/adr/README.md`)
- **Runbooks:** `docs/operations/`
- **Contributor guidance:** `.claude/`
