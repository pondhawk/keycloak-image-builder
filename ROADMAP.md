# KDT Roadmap

KDT is a **model-instance build tool**. On the golden/model instance it does
three things: **install/update** Keycloak, **validate** the install, and
**prepare it for imaging**. Runtime — boot config, clustering, scaling, upgrade,
rollback — is handled by the baked-in systemd units + AWS + operational
runbooks, **not** by `kcadmin`.

## Commands (the whole surface)

| Command | Purpose | Status |
|---------|---------|--------|
| `install` | Install/update Keycloak on the model: Java, distribution, dirs, service user, neutral `keycloak.conf`, `kc.sh build`, SELinux contexts | ✅ |
| `verify` | Validate the install: Java, install, build, config, SELinux Enforcing, systemd units | ✅ |
| `ami-clean` | Sanitize for imaging + neutrality gate (`--check` runs the gate only) | ✅ |
| `version` | Toolkit + Keycloak/Java baseline versions | ✅ |

The typical model-instance bake:

```
kcadmin install --keycloak-version 26.1.4 --db-vendor mysql
kcadmin verify
kcadmin ami-clean         # then create the AMI in the AWS Console
```

## Remaining

- ~~Boot secret-fetch (ADR-0008)~~ — **done**: `boot/configure-node.sh` reads
  IMDSv2 + fetches the cluster's JSON secret and splits it (secret→tmpfs,
  non-secret→`keycloak.env`). The split is Bats-tested; the live IMDS/AWS path is
  exercised by the real-instance test below. Uses AWS CLI v2 + `jq` (documented
  model prerequisites — KDT does not install third-party tooling).
- Real-instance test on a RHEL-family 10 host, e.g. Rocky Linux 10 (install → verify → ami-clean → image).
- Operational docs: upgrade runbook, OS-patching runbook (ADR-0013), README polish.
- **Centralized logging** (Fluent Bit → CloudWatch, ADR-0010) — deferred
  follow-up; `fluent-bit` isn't in base RHEL repos, so re-evaluate packaging
  (vs. the CloudWatch agent) when implemented. On-node journald logging works today.

## Note on scope

The blueprint §19 listed 11 milestones and §11 an 18-command CLI. We consolidated
to the 4 commands above: the pets-oriented commands (`start`/`stop`/`restart`/
`status`/`logs`/`journal`/`cluster`/`upgrade`/`rollback`/`health`/`check`/
`configure`/`build`/`selinux`) were dropped or folded, because in the cattle /
immutable-AMI model nobody runs commands on production nodes — the toolkit's job
is to build a clean image. The decisions themselves remain recorded in the ADRs.
