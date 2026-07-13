# Runbook — Fresh install

Build a golden Keycloak model from a bare RHEL-family 9+ instance for the first
time, and leave it **ready for image creation**.

Use this when: you have a new model instance and no existing Keycloak install on
it. To reset an instance that already has one, use
[Clean install](clean-install.md).

---

## Before you start

- **`kcimage` is on your `PATH`.** If not, do
  [Install the toolkit](../../README.md#install-the-toolkit) first — it is a
  required one-time step.
- **SELinux is Enforcing** — the bake and `verify` require it:
  ```bash
  getenforce        # must print: Enforcing
  ```
- You know the **Keycloak version** (e.g. `26.1.4`) and the **DB vendor**
  (`postgres` or `mysql`) this image is for. The vendor is baked in — one image per
  vendor.
- **Architecture:** the image is built for **this instance's CPU arch** (x86_64
  or ARM64/aarch64) — KIB can't cross-build, so build on the arch you'll run
  (a Graviton instance for an ARM64 image). Add `--arch x64|arm64` to `install`
  to assert you're on the intended arch.
- **(Optional) custom providers:** drop provider JARs (themes ship as JARs too)
  into `~/keycloak-custom-providers/` now, before installing:
  ```bash
  cp my-provider.jar ~/keycloak-custom-providers/
  ```

---

## Workflow

### 1. Confirm the toolkit version

Check that `kcimage` is the version you expect. If you just installed a new
release, a forgotten `bootstrap.sh` leaves the previous toolkit on your `PATH` —
and it would build the old layout. Every command also prints a
`=== kcimage <version> ===` banner as a backstop.

```bash
kcimage version
```

### 2. (Optional) preview the install

See exactly what will happen, changing nothing:

```bash
kcimage --dry-run install --keycloak-version 26.1.4 --db-vendor postgres
```

### 3. Install and bake the model

Installs OpenJDK 21 and the Keycloak distribution into `/opt/keycloak`
(`KEYCLOAK_HOME`), creates the service user, renders the neutral
`conf/keycloak.conf`, deploys your custom providers, runs `kc.sh build`, and lays
down the systemd units, boot script, and SELinux contexts. Everything
server-side lives under `/opt/keycloak` — one version, no versioned subdir.

```bash
sudo kcimage install --keycloak-version 26.1.4 --db-vendor postgres
```

For a MySQL image, swap the vendor (build a separate image):

```bash
sudo kcimage install --keycloak-version 26.1.4 --db-vendor mysql
```

### 4. Verify the install

Offline gate — Java, the install, `kc.sh build`, config, SELinux Enforcing, the
systemd units, and that **every** custom provider JAR landed. Fix any `FAIL`
before continuing.

```bash
sudo kcimage verify
```

### 5. Seal for imaging

Removes secrets, environment-specific config, runtime state, and machine
identity, then runs the neutrality gate and **fails if anything sensitive
remains**. Re-run the gate alone any time with `kcimage seal --check`.

```bash
sudo kcimage seal
```

---

## ✅ Ready for image creation

The model is now environment-neutral and sanitized. **Do not boot Keycloak or
run any further `kcimage` command on it** — that would re-introduce state.

➡️ Continue in the [**Deploy to AWS**](deploy-aws.md) runbook to create the image
and roll it to your Auto Scaling Group.

---

## Troubleshooting

- **`verify` reports `[FAIL] SELinux`** — SELinux is not Enforcing. Set it
  (`setenforce 1` and fix `/etc/selinux/config`), then re-run.
- **`verify` reports `[FAIL] providers` listing a JAR** — the JAR is in
  `~/keycloak-custom-providers` but didn't reach the install. Re-deploy with
  `kcimage upgrade --keycloak-version <this version>` (same version re-renders,
  re-deploys providers, and rebuilds), then `verify` again.
- **`install` says `already installed`** — `install` is greenfield-only. This
  model already has an install; use [Upgrade](upgrade-install.md) to change the
  version, or [Clean install](clean-install.md) to start over.
- **`seal` fails the neutrality gate** — something environment-specific is still
  present (an env value or secret). The failure names it; remove it and re-run
  `kcimage seal`.
