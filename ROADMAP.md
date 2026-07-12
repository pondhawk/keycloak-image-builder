# KIB Roadmap

KIB is a **model-instance build tool**. On the golden/model instance it does
three things: **install/update** Keycloak, **validate** the install, and
**prepare it for imaging**. Runtime — boot config, clustering, scaling, upgrade,
rollback — is handled by the baked-in systemd units + AWS + operational
runbooks, **not** by `kcimage`.

## Commands (the whole surface)

| Command | Purpose | Status |
|---------|---------|--------|
| `install` | Install/update Keycloak on the model: Java, distribution, dirs, service user, neutral `keycloak.conf`, `kc.sh build`, SELinux contexts | ✅ |
| `verify` | Validate the install: Java, install, build, config, SELinux Enforcing, systemd units | ✅ |
| `seal` | Sanitize for imaging + neutrality gate (`--check` runs the gate only) | ✅ |
| `clean` | Invert `install` — return the model to a pristine state (testing); `--yes` to apply | ✅ |
| `version` | Toolkit + Keycloak/Java baseline versions | ✅ |

The typical model-instance bake:

```
kcimage install --keycloak-version 26.1.4 --db-vendor mysql
kcimage verify
kcimage seal         # then create the AMI in the AWS Console
```

## Remaining

- ~~Boot config (ADR-0008)~~ — **done**: `boot/configure-node.sh` reads IMDSv2
  (private IP) + launch-template user-data (`KEY=VALUE`, `KC_*` names) and splits
  it (secret→tmpfs, non-secret→`keycloak.env`). Bats-tested; the live IMDS path is
  exercised by the real-instance test below. **No AWS CLI, no `jq`** — Secrets
  Manager was dropped for user-data (simpler, fewer boot dependencies).
- Real-instance test on a RHEL-family 10 host, e.g. Rocky Linux 10 (install → verify → seal → image).
- Operational docs: upgrade runbook, OS-patching runbook (ADR-0013), README polish.
- **Centralized logging** (Fluent Bit → CloudWatch, ADR-0010) — deferred
  follow-up; `fluent-bit` isn't in base RHEL repos, so re-evaluate packaging
  (vs. the CloudWatch agent) when implemented. On-node journald logging works today.

## Note on scope

The blueprint §19 listed 11 milestones and §11 an 18-command CLI. We consolidated
to the four core commands above (plus `clean`, a testing convenience): the
pets-oriented commands (`start`/`stop`/`restart`/
`status`/`logs`/`journal`/`cluster`/`upgrade`/`rollback`/`health`/`check`/
`configure`/`build`/`selinux`) were dropped or folded, because in the cattle /
immutable-AMI model nobody runs commands on production nodes — the toolkit's job
is to build a clean image. The decisions themselves remain recorded in the ADRs.
