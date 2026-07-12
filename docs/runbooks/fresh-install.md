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
  (`postgres` or `mysql`) this AMI is for. The vendor is baked in — one AMI per
  vendor.
- **(Optional) custom providers:** drop provider JARs (themes ship as JARs too)
  into `~/keycloak-custom-providers/` now, before installing:
  ```bash
  cp my-provider.jar ~/keycloak-custom-providers/
  ```

---

## Workflow

### 1. (Optional) preview the install

See exactly what will happen, changing nothing:

```bash
kcimage --dry-run install --keycloak-version 26.1.4 --db-vendor postgres
```

### 2. Install and bake the model

Installs OpenJDK 21, the Keycloak distribution, the service user and
directories, the neutral `keycloak.conf`, your custom providers, runs
`kc.sh build`, and lays down the systemd units, boot script, and SELinux
contexts. `--activate` points `/opt/keycloak/current` at this version.

```bash
sudo kcimage install --keycloak-version 26.1.4 --db-vendor postgres --activate
```

For a MySQL AMI, swap the vendor (build a separate AMI):

```bash
sudo kcimage install --keycloak-version 26.1.4 --db-vendor mysql --activate
```

### 3. Verify the install

Offline gate — Java, the install, `kc.sh build`, config, SELinux Enforcing, the
systemd units, and that **every** custom provider JAR landed. Fix any `FAIL`
before continuing.

```bash
sudo kcimage verify
```

### 4. Seal for imaging

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

➡️ Continue in the [**Deploy to AWS**](deploy-aws.md) runbook to create the AMI
and roll it to your Auto Scaling Group.

---

## Troubleshooting

- **`verify` reports `[FAIL] SELinux`** — SELinux is not Enforcing. Set it
  (`setenforce 1` and fix `/etc/selinux/config`), then re-run.
- **`verify` reports `[FAIL] providers` listing a JAR** — the JAR is in
  `~/keycloak-custom-providers` but didn't reach the install. Re-run
  `kcimage install …` (it re-deploys providers), then `verify` again.
- **`seal` fails the neutrality gate** — something environment-specific is still
  present (an env value or secret). The failure names it; remove it and re-run
  `kcimage seal`.
