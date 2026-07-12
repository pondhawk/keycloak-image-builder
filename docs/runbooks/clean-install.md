# Runbook — Clean install

Reset a model instance to a **pristine state** and build a fresh golden model,
leaving it **ready for image creation**.

Use this when: the model already has a KIB install you want to discard — a
botched bake, a test run, or a model you're repurposing for a different Keycloak
version or DB vendor.

> `clean` inverts `install`, **not** `bootstrap`. It keeps the toolkit
> (`kcimage`), OpenJDK, and your `~/keycloak-custom-providers`. It removes
> Keycloak, config, runtime state, the systemd units, the boot script, the
> service user, and the SELinux rules.

---

## Before you start

- **`kcimage` is on your `PATH`** ([Install the toolkit](../../README.md#install-the-toolkit)).
- **SELinux Enforcing:**
  ```bash
  getenforce        # must print: Enforcing
  ```

---

## Workflow

### 1. Preview what will be removed

`clean` is destructive; always look first. A dry run changes nothing and prints
exactly what a real run would remove (or `already clean` if there's nothing).

```bash
kcimage --dry-run clean
```

### 2. Clean the instance

`clean` prompts for confirmation before removing anything (there is no `--yes`
bypass — that's deliberate). Type `y` when asked. (Add `--purge-java` only if you
also want OpenJDK removed — normally leave it, so the next install is faster.)

```bash
sudo kcimage clean
```

### 3. Confirm it's pristine

```bash
kcimage --dry-run clean        # should report: already clean
```

### 4. Fresh install

The instance is now equivalent to a bare model. Do a full
[Fresh install](fresh-install.md):

```bash
# (optional) preview
kcimage --dry-run install --keycloak-version 26.1.4 --db-vendor postgres

# install (activates by default)
sudo kcimage install --keycloak-version 26.1.4 --db-vendor postgres

# verify
sudo kcimage verify

# seal
sudo kcimage seal
```

---

## ✅ Ready for image creation

The model is freshly installed and sealed.

➡️ Continue in the [**Deploy to AWS**](deploy-aws.md) runbook.

---

## Troubleshooting

- **`clean` left something behind** — re-run `kcimage --dry-run clean` to see
  what remains; a stubborn systemd unit usually clears with a
  `sudo systemctl daemon-reload` and another `sudo kcimage clean`.
- **You want a different DB vendor than before** — `clean` then install with the
  new `--db-vendor`; the vendor is baked at `install` time, so a clean install
  is exactly how you switch it.
