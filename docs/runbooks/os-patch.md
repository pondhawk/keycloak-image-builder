# Runbook — OS patch / image refresh

Apply OS security patches to the model, **keeping the same Keycloak version**,
and leave it **ready for image creation**. The resulting image rolls out
**zero-downtime** (ADR-0013).

Use this when: you are applying OS/kernel/library updates but **not** changing
the Keycloak version. To change the Keycloak version, use
[Upgrade Keycloak](upgrade-install.md) instead.

> **Why this is different from an upgrade.** An OS-only patch changes no Keycloak
> version, triggers no Liquibase schema migration, and carries no mixed-version
> risk — so the image is deployed with a **rolling ASG instance refresh**, not the
> scale-to-0 cutover, and rollback is just re-pointing the launch template. The
> deploy side is in [Deploy to AWS](deploy-aws.md).

---

## Before you start

- **`kcimage` is on your `PATH`** ([Install the toolkit](../../README.md#install-the-toolkit)).
- Use the model instance whose image lineage you are patching; **the Keycloak
  version stays exactly as-is.**
- **SELinux Enforcing:**
  ```bash
  getenforce        # must print: Enforcing
  ```

---

## Workflow

### 1. Confirm the toolkit and starting state

First confirm you're running the `kcimage` you expect — a forgotten
`bootstrap.sh` after a release leaves the previous toolkit on your `PATH`. Then
record the Keycloak version: the deployed image must be tagged with it, and the
rolling refresh keys off it matching.

```bash
kcimage version            # check the toolkit version AND record the Keycloak baseline
sudo kcimage verify        # should be all green before you patch
```

### 2. Apply OS updates

A full update of every OS package — this is what makes the image "patched."

```bash
sudo dnf -y update
```

### 3. Reboot if the kernel or core libraries changed

```bash
sudo dnf needs-restarting -r || sudo reboot
```

After the reboot, log back in and confirm SELinux is still Enforcing
(`getenforce`).

### 4. Re-verify

Confirm the patch didn't disturb the install — **same Keycloak version**, all
checks green.

```bash
sudo kcimage verify
```

### 5. Seal for imaging

```bash
sudo kcimage seal
```

---

## ✅ Ready for image creation

The model is patched and sealed at the **unchanged** Keycloak version.

➡️ Continue in [**Deploy to AWS**](deploy-aws.md) → **"OS patch (rolling instance
refresh)."** Tag the new image with the same Keycloak version and a fresh
`build-date` so it's distinguishable from its predecessor. `kcimage`/the refresh
path **refuses a rolling refresh if the Keycloak-version tag differs** — that
case must use the [Upgrade](upgrade-install.md) path.

---

## Troubleshooting

- **Kernel updated but node behaves oddly after boot** — ensure you rebooted the
  model *before* sealing, so the image captures the running patched kernel.
- **`verify` shows a different Keycloak version than step 1** — you accidentally
  changed the install. This is no longer an OS-only patch; either revert or
  follow the [Upgrade](upgrade-install.md) runbook and deploy via scale-to-0.
