# KIB Roadmap

KIB is a **model-instance build tool**. On the golden/model instance it does
three things: **install/update** Keycloak, **validate** the install, and
**prepare it for imaging**. Runtime — boot config, clustering, scaling, and the
**cluster** upgrade/rollback — is handled by the baked-in systemd units + AWS +
operational runbooks, **not** by `kcimage`.

## Commands (the whole surface)

| Command | Purpose | Status |
|---------|---------|--------|
| `install` | Establish a fresh install (greenfield) on a clean model, all under `/opt/keycloak`: Java, distribution, service user, neutral `conf/keycloak.conf`, `kc.sh build`, systemd units, SELinux contexts | ✅ |
| `upgrade` | Move an existing install to a new Keycloak version (DB vendor inherited from the existing install) | ✅ |
| `verify` | Validate the install: Java, install, build, config, SELinux Enforcing, systemd units | ✅ |
| `seal` | Sanitize for imaging + neutrality gate (`--check` runs the gate only) | ✅ |
| `clean` | Invert `install` — return the model to a pristine state (testing) | ✅ |
| `version` | Toolkit + Keycloak/Java baseline versions | ✅ |

The typical model-instance bake:

```
kcimage install --keycloak-version 26.1.4 --db-vendor mysql
kcimage verify
kcimage seal         # then create the AMI in the AWS Console
```

## Status

The toolkit, its docs, and **real-instance validation** are **complete** — the
toolkit is proven end-to-end on a real host.

**Done:**

- ~~Real-instance validation~~ — the `install → verify → seal → image → deploy`
  flow exercised on a real **RHEL-family 10** node (Rocky Linux 10).
- ~~All six commands~~ — `install`/`upgrade`/`verify`/`seal`/`clean`/`version`
  (see the table above).
- ~~`install`/`upgrade` split~~ — greenfield `install`; `upgrade` inherits the DB
  vendor from the model, so a vendor mismatch is impossible by construction.
- ~~CLI safety~~ — interactive confirmation on every mutating command (no
  `--yes` bypass), and a hard **Keycloak 26+** floor enforced on the model.
- ~~Custom providers~~ — `~/keycloak-custom-providers` (operator-owned), deployed
  and re-built on every `install`/`upgrade`.
- ~~Boot config (ADR-0008)~~ — `boot/configure-node.sh` reads IMDSv2 (private IP)
  + launch-template user-data (`KEY=VALUE`, `KC_*`), writing both `keycloak.env`
  and `secrets.env` to tmpfs `/run/keycloak` so nothing environment-specific
  touches disk. **No AWS CLI, no `jq`** (Secrets Manager dropped for user-data).
  Bats-tested; the live IMDS path is exercised by real-instance validation.
- ~~Operational docs~~ — the README is a runbook hub, with self-contained runbooks
  in `docs/runbooks/` (fresh, upgrade, os-patch, clean, deploy-to-AWS).

**Deferred (out of current scope, not blocking):**

- **Centralized logging** (Fluent Bit → CloudWatch, ADR-0010) — `fluent-bit`
  isn't in base RHEL repos, so re-evaluate packaging (vs. the CloudWatch agent)
  when implemented. On-node journald logging works today.

## Note on scope

The blueprint §19 listed 11 milestones and §11 an 18-command CLI. We consolidated
to the five focused model-build commands above (plus `clean`, a testing
convenience): the pets-oriented commands (`start`/`stop`/`restart`/`status`/
`logs`/`journal`/`cluster`/`rollback`/`health`/`check`/`configure`/`build`/
`selinux`) were dropped or folded, because in the cattle / immutable-AMI model
nobody runs commands on production nodes — the toolkit's job is to build a clean
image. Note `upgrade` here is the **model-side** version bump (it produces a new
image); the **cluster** upgrade/rollback (scale-to-0 cutover, ADR-0006/0007)
stays an AWS + ASG operation, not a toolkit command. The decisions themselves
remain recorded in the ADRs.
