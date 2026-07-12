# Runbook — Upgrade Keycloak

Move the model to a **new Keycloak version**, side-by-side with the old one, and
leave it **ready for image creation**. This produces a new image at the new
version.

Use this when: you are changing the **Keycloak version** (e.g. `26.1.4` →
`26.2.0`). For OS security patches at the *same* Keycloak version, use
[OS patch / image refresh](os-patch.md) instead — it rolls out zero-downtime.

> **This is a schema-migrating change.** The image you build here is deployed with
> the **scale-to-0 cutover** (ADR-0006), which has a planned downtime window and
> a mandatory RDS snapshot. That happens on the AWS side — see
> [Deploy to AWS](deploy-aws.md). This runbook only builds the image.

---

## Before you start

- **`kcimage` is on your `PATH`** ([Install the toolkit](../../README.md#install-the-toolkit)).
- **Use the model instance that already has the install you're upgrading.**
  The DB vendor is inherited from that install, so an upgrade can never change
  the image's baked vendor. (A model with no install yet is a
  [Fresh install](fresh-install.md), not an upgrade.)
- **SELinux Enforcing:**
  ```bash
  getenforce        # must print: Enforcing
  ```
- Your `~/keycloak-custom-providers/` still holds the providers you want — they
  are re-deployed and re-built against the new version automatically.

---

## Workflow

### 1. (Optional) preview

```bash
kcimage --dry-run upgrade --keycloak-version 26.2.0
```

### 2. Upgrade to the new version (side-by-side, activated)

The new version installs under `/opt/keycloak/keycloak-<new>` next to the old
one, and `upgrade` **activates it** — switching the `/opt/keycloak/current`
symlink to it **on this model instance only**. The DB vendor, custom providers,
and config carry over from the existing install; `kc.sh build` runs for the new
version.

```bash
sudo kcimage upgrade --keycloak-version 26.2.0
```

### 3. Verify

```bash
sudo kcimage verify
```

Confirm it reports the new version and every check passes.

### 4. Seal for imaging

`seal` also prunes the old, non-`current` Keycloak versions so they don't
accumulate into the image — only the activated version is kept.

```bash
sudo kcimage seal
```

---

## ✅ Ready for image creation

The model is sealed at the new Keycloak version.

➡️ Continue in [**Deploy to AWS**](deploy-aws.md) → **"Upgrade Keycloak
(scale-to-0 cutover)"**. Note the mandatory pre-upgrade **RDS snapshot** — the
cutover refuses to proceed without a recent one.

---

## Troubleshooting

- **`no existing install found`** — this model has no install to upgrade. Do a
  [Fresh install](fresh-install.md) instead (`install --db-vendor …`).
- **Provider incompatible with the new version** — `kc.sh build` (inside
  `upgrade`) will fail. Update the provider JAR in `~/keycloak-custom-providers`
  for the new Keycloak version and re-run `upgrade`.
- Other failures behave exactly as in [Fresh install](fresh-install.md#troubleshooting).
