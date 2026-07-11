# Architecture Decision Records

KDT uses the [Nygard ADR format](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions)
(Status · Context · Decision · Consequences). Per blueprint §21, implementation
begins only after the relevant ADRs are **Accepted**.

| ADR | Title | Status |
|-----|-------|--------|
| [0001](0001-directory-structure.md) | Directory Structure | Accepted |
| [0002](0002-configuration-hierarchy.md) | Configuration Hierarchy | Accepted |
| [0003](0003-database-engine-strategy.md) | Database Engine Strategy | Accepted |
| [0004](0004-ami-and-build-strategy.md) | AMI & Build Strategy | Accepted |
| [0005](0005-systemd-service-design.md) | systemd Service Design | Accepted |
| [0006](0006-upgrade-strategy.md) | Upgrade Strategy | Accepted |
| [0007](0007-rollback-strategy.md) | Rollback Strategy | Accepted |
| [0008](0008-secrets-management.md) | Secrets Management | Accepted |
| [0009](0009-clustering-jdbc-ping2.md) | Clustering (JDBC_PING2) | Accepted |
| [0010](0010-logging.md) | Logging | Accepted |
| [0011](0011-selinux.md) | SELinux | Accepted |
| [0012](0012-testing.md) | Testing | Accepted |

Status values: **Planned** → **Proposed** (drafted, awaiting review) →
**Accepted** / **Rejected** → **Superseded** (by a later ADR).

> Note: this set adds two ADRs beyond blueprint §18 — **0003 Database Engine
> Strategy** and **0008 Secrets Management** — and promotes systemd design to
> its own record (**0005**), because each carries a significant, independent
> decision.
