# Keycloak Image Builder (KIB)

`kcimage` — a Bash CLI that turns a fresh **RHEL-family 9+** instance into a
**golden Keycloak model**, then sanitizes it so you can bake an
environment-neutral **image** that an autoscaling fleet launches.

> **Status:** v1.0.0 — the toolkit is complete and CI is green. Real-instance
> validation on RHEL-family 9 is underway. See `ROADMAP.md`.

KIB is a **model-instance build tool**, not a production-node console (nodes are
cattle). On the model instance it does exactly three things —
**install/update → verify → prepare-for-image** — and then you bake an image from
it. Everything a running node needs is either baked into the image or injected at
boot from instance user-data; nobody ever runs `kcimage` on a production node.

---

## Requirements

**Operating system — the model instance and the nodes**

- **RHEL-family 9 or above** — Rocky Linux, AlmaLinux, RHEL, Oracle Linux, or
  CentOS Stream (Fedora works too). RHEL 8 has no known blocker but is unverified.
- The requirement is really its toolchain, not a brand: **`dnf`**, **SELinux in
  Enforcing mode**, **systemd**, and a **`java-21-openjdk`** package in the
  repos. This rules out SUSE/SLES (`zypper`) and Debian/Ubuntu (`apt` +
  AppArmor, not SELinux).

**Architecture**

- **x86_64 or ARM64/aarch64.** Keycloak's distribution is architecture-independent
  and OpenJDK is `dnf`-resolved per host, so both work with no special handling.
  KIB builds for the host arch and **cannot cross-build** — build the model on the
  arch you intend to run. `install --arch x64|arm64` asserts the intended arch.

**Access & network**

- **root** on the model instance (`sudo`).
- Outbound internet from the model instance to download the Keycloak
  distribution.

**Database** — KIB never creates, migrates, or owns your data.

- A **reachable, already-populated** database: **PostgreSQL** or **MySQL**,
  running on a managed service, a self-managed host, or a container — KIB doesn't
  care where.
- Supported engine versions track the Keycloak release you install
  ([source of truth](https://www.keycloak.org/server/db)). For Keycloak 26.x:

  | Engine | `--db-vendor` | Supported versions |
  |--------|---------------|--------------------|
  | PostgreSQL | `postgres` | 14.x – 18.x |
  | MySQL | `mysql` | 8.0, 8.4 (LTS) — 5.7 is **not** supported |

- **The DB vendor is baked in at build time** (it drives `kc.sh build`), so a
  golden image is Postgres **or** MySQL — build one image per vendor you run.

**Keycloak version**

- **26.x or newer.** `install`/`upgrade` **refuse** older majors — the baked
  config is Keycloak 26-era (jdbc-ping cache stack, `KC_BOOTSTRAP_ADMIN_*`,
  management port), and an older server would pass the model gates but fail at
  node boot. Newer majors are allowed with a warning (untested).

---

## Install the toolkit

**Required first step for every runbook below.** Download the latest release,
extract it, and run `bootstrap.sh` to put `kcimage` on your `PATH`. (`make` is
*not* needed on the model instance — `kcimage install` bakes everything the image
needs.)

Open the latest release and copy the `kcimage-<version>.tar.gz` asset URL:

<https://github.com/pondhawk/keycloak-image-builder/releases/latest>

Then paste it in place of `<URL>` below:

```bash
curl -fsSL -o kcimage.tar.gz "<URL>"
tar xzf kcimage.tar.gz
cd kcimage-*/
sudo ./bootstrap.sh          # installs kcimage to /usr/local/bin
```

Confirm it's on your `PATH`:

```bash
kcimage version
```

You'll run most commands with `sudo` (install/seal/clean need root). `bootstrap.sh`
symlinks `/usr/sbin/kcimage → /usr/local/bin/kcimage` so `sudo kcimage` resolves
even on hardened images that keep `/usr/local/bin` out of sudo's `secure_path`
(otherwise you'd get `sudo: kcimage: command not found` — use the full path
`sudo /usr/local/bin/kcimage …` as a fallback).

`bootstrap.sh` also creates **`~/keycloak-custom-providers/`** — drop custom
provider JARs (themes ship as JARs too) there before installing and every bake
picks them up. To upgrade the toolkit later, download a newer release and run
`sudo ./bootstrap.sh` again; it overwrites in place, so `kcimage` always points
at the latest and no versioned path ever lands in your shell history.

---

## Runbooks

Each runbook is **self-contained** — read the workflow, copy-paste the commands
into a terminal on the model instance, top to bottom. Every model-instance
runbook ends at the same hard stop: **✅ the model is ready for image creation.**
From there, the **Deploy to AWS** runbook takes over.

| Runbook | Use it when you want to… | Runs on |
|---------|--------------------------|---------|
| [**Fresh install**](docs/runbooks/fresh-install.md) | Build a golden model from a bare instance for the first time | Model instance |
| [**Upgrade Keycloak**](docs/runbooks/upgrade-install.md) | Move the model to a new Keycloak version (safe in-place swap, then re-bake) | Model instance |
| [**OS patch / image refresh**](docs/runbooks/os-patch.md) | Apply OS security patches and re-bake the same Keycloak version | Model instance |
| [**Clean install**](docs/runbooks/clean-install.md) | Reset the model to a pristine state and start over | Model instance |
| [**Deploy to AWS**](docs/runbooks/deploy-aws.md) | Create the image, wire the launch template + user-data, and roll it to the ASG | AWS |

Every command supports a preview that changes nothing:

```bash
kcimage --dry-run install --keycloak-version 26.1.4 --db-vendor postgres
kcimage --verbose <command>    # debug-level logging
kcimage <command> --help       # per-command usage
```

The mutating commands (`install`, `upgrade`, `seal`, `clean`) **prompt for
confirmation** before doing anything. There is deliberately no `--yes`/`--force`
bypass — a flag like that, sitting in your shell history, would defeat the
prompt on an accidental up-arrow re-run. Use `--dry-run` to preview
non-interactively; automation is intentionally not a goal for these. They also
**refuse to run while `keycloak.service` is active** — that means you're on a
live cluster node (the toolkit is baked into the image), not the model instance,
so they stop rather than damage it.

---

## Command reference

The runbooks above are the intended path; this is the flat reference.

| Command | What it does |
|---------|--------------|
| `install` | Establish a **fresh** Keycloak install (lineage) on a clean model, all under `/opt/keycloak`: Java, distribution, service user, neutral `conf/keycloak.conf`, custom providers, `kc.sh build`, systemd units + boot script, SELinux contexts. Greenfield-only (refuses over an existing install — `clean` first). Requires `--keycloak-version` and `--db-vendor`. Runs on **x86_64 or ARM64/aarch64** — Keycloak is arch-independent and Java is dnf-resolved per host, so the image's arch is simply the arch of the model you build on. Optional `--arch x64\|arm64` asserts the host matches and refuses on mismatch (KIB can't cross-build). |
| `upgrade` | Move an **existing** install to a new Keycloak version via a **safe in-place swap** (old moved to `/opt/keycloak.bak`, new built, backup deleted last on success; rolls back on failure). Inherits the DB vendor from the existing install, so an upgrade can't change the baked vendor. Requires `--keycloak-version`. |
| `verify` | Offline pre-seal validation: Java, install, build, config, SELinux Enforcing, systemd units, and that every custom provider landed. Exits non-zero on any failure. |
| `seal` | Sanitize the instance for imaging (remove secrets, env config, runtime state, machine identity) and run the neutrality gate. `--check` runs the gate only. |
| `clean` | Invert `install`, returning the model to a pristine state. Keeps the toolkit, OpenJDK, and `~/keycloak-custom-providers`. Mostly for testing. |
| `version` | Show the KIB, Keycloak-baseline, and Java versions. |

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
- **Runbooks:** `docs/runbooks/`
- **Operations (rollback, etc.):** `docs/operations/`
- **Contributor guidance:** `.claude/`
