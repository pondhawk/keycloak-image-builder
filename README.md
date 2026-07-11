# Keycloak Deployment Toolkit (KDT)

A Bash CLI toolkit (`kcadmin`) that installs, configures, validates, and
lifecycle-manages **Keycloak 26.x** on **Rocky Linux 10 / systemd / SELinux
Enforcing**, integrated with **AWS**. KDT builds an environment-neutral **golden
AMI** that an **Auto Scaling Group** turns into a production Keycloak cluster.

> Status: **early scaffolding** (v0.1.0). Milestone 1 (ADRs) complete;
> Milestone 2 (scaffolding) in progress. See `ROADMAP.md`.

## Documentation

- **Architecture blueprint:** `Keycloak_Deployment_Toolkit_Architecture_Blueprint.md`
- **Decisions (ADRs):** `docs/adr/` — all 12 Accepted (`docs/adr/README.md`)
- **Operations runbooks:** `docs/operations/`
- **Contributor guidance:** `.claude/` (coding standards, project rules)

## At a glance

- **Two DB engines** — PostgreSQL (default) and MySQL, both first-class.
- **Immutable upgrades** — scale-to-0 cutover to a new per-vendor AMI.
- **Secrets** — AWS Secrets Manager → tmpfs, never in the AMI.
- **Clustering** — built-in JDBC_PING2 stack over the shared RDS.
- **TLS** — terminated at the ALB (ACM); nodes serve plain HTTP.

## Development

```bash
make check    # ShellCheck + shfmt
make test     # Bats
make install  # install kcadmin (golden instance)
make package  # build the release tarball
```

## The `kcadmin` command

```
kcadmin [--dry-run] [--verbose] <command>
```

Commands (blueprint §11): `install configure build check version start stop
restart status logs journal health verify cluster upgrade rollback ami-clean`.
Most are skeletons pending their implementation milestone.
