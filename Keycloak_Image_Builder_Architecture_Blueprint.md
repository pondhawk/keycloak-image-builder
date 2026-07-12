# Keycloak Image Builder

## Enterprise Architecture Blueprint

### Version 1.0

> This document is the authoritative specification for implementing the
> Keycloak Image Builder (KIB). It is intended for use by Claude
> Code as the sole architectural reference for the project.

------------------------------------------------------------------------

# 1. Executive Summary

The Keycloak Image Builder (KIB) is an enterprise-grade deployment
and lifecycle management framework for Keycloak running on AWS.

The toolkit is designed to create repeatable, supportable,
production-quality Keycloak installations that can be deployed from a
golden AMI with minimal manual intervention.

The toolkit is not simply an installer. It is an operational platform.

------------------------------------------------------------------------

# 2. Core Objectives

-   Fully automate Keycloak installation.
-   Automate upgrades and validation.
-   Support rolling cluster upgrades.
-   Produce reusable EC2 AMIs.
-   Keep deployments environment-neutral.
-   Minimize manual operational tasks.
-   Preserve rollback capability.
-   Maintain comprehensive documentation.

------------------------------------------------------------------------

# 3. Target Platform

Operating System: - RHEL-family 10 (Rocky Linux 10 is the reference target;
AlmaLinux 10 / RHEL 10 also supported — requires dnf + SELinux)

Keycloak: - 26.x (default baseline; toolkit is version-parameterized)

Java: - OpenJDK 21 (installed via dnf, managed by alternatives)

Cloud: - AWS EC2

Database: - Amazon RDS for PostgreSQL (default) or Amazon RDS for MySQL -
Existing database - Existing database user - Toolkit never creates
databases. - Both engines are first-class and tested equally; engine is a
configuration axis (`db.vendor`).

Load Balancer: - AWS Application Load Balancer

Cluster Discovery: - JGroups JDBC_PING2

Init System: - systemd

Security: - SELinux Enforcing

Secrets: - Launch-template user-data (DB credentials + config as
KEY=VALUE); read at boot, secret keys to tmpfs, never baked into the AMI.

Deployment Model: - Multi-node Keycloak cluster

------------------------------------------------------------------------

# 4. Architecture Principles

1.  Architecture before code.
2.  Idempotent operations.
3.  Immutable versioned installations.
4.  Environment-neutral AMIs.
5.  Fail safely.
6.  Never overwrite a working installation.
7.  Every change is documented.
8.  Every feature is tested.
9.  Every operational step is scriptable.

------------------------------------------------------------------------

# 5. Repository Layout

``` text
keycloak-image-builder/
├── .claude/
│   ├── CLAUDE.md
│   ├── coding-standards.md
│   ├── architecture.md
│   └── project-rules.md
├── docs/
│   ├── adr/
│   ├── architecture/
│   ├── operations/
│   ├── troubleshooting/
│   └── images/
├── scripts/
├── systemd/
├── selinux/
├── templates/
├── tests/
├── examples/
├── Makefile
├── README.md
├── CHANGELOG.md
└── ROADMAP.md
```

------------------------------------------------------------------------

# 6. Filesystem Layout

``` text
/usr/lib/jvm/
    <openjdk-21>                      (installed via dnf, managed by alternatives)

/opt/keycloak/                        (Role A: installations)
    keycloak-<version>/
    current -> keycloak-<version>

/opt/keycloak-custom/                 (Role B: source-controlled custom provider JARs)
    providers/                        (themes ship as provider JARs too)

/etc/keycloak/                        (config)
    keycloak.conf
    keycloak.env
    bootstrap.env

/var/lib/keycloak/                    (Role C: runtime state)
/var/log/keycloak/
/var/backups/keycloak/
```

Only the `current` symbolic link changes during upgrades.

------------------------------------------------------------------------

# 7. Configuration Model

## keycloak.conf

Platform configuration only.

Examples:

-   cache
-   clustering
-   metrics
-   proxy
-   logging
-   health

## keycloak.env

Environment-specific values.

Examples:

-   hostname
-   RDS endpoint
-   DB username
-   JVM memory
-   Java options

## bootstrap.env

Temporary administrator credentials.

Automatically removed after successful initialization.

------------------------------------------------------------------------

# 8. Customizations

Custom providers are source-controlled outside the Keycloak installation.
Themes ship as provider JARs too (best practice), so they go here as well.

Store source assets under:

-   /opt/keycloak-custom/providers

Deploy into the active installation (`/opt/keycloak/current`) before
running `kc.sh build`.

------------------------------------------------------------------------

# 9. Cluster Design

-   JDBC_PING2
-   Shared Amazon RDS MySQL database
-   AWS ALB
-   Private subnets
-   Self-referencing security-group rules for cluster traffic
-   Health and metrics enabled

Validation must verify:

-   Cluster membership
-   Cluster size
-   Health endpoint
-   Metrics endpoint
-   OIDC discovery
-   Admin Console availability

------------------------------------------------------------------------

# 10. Upgrade Strategy

Upgrades are **immutable**. This is the canonical production path.

Production upgrade (ASG):

-   Bake a new AMI on the new Keycloak version.
-   Update the launch template to the new AMI.
-   Roll the fleet with an ASG instance refresh (drain, replace,
    health-check).
-   Never mutate live production nodes.

Production rollback (ASG):

-   Re-point the launch template to the previous AMI.
-   Instance-refresh back. The previous AMI is the rollback artifact.

Golden-instance version prep (not production):

-   Install new versions side-by-side.
-   Build before activation.
-   Switch the `current` symlink after validation.
-   Preserve previous installation.
-   Used only on the golden instance to prepare, test, and validate a
    version before baking the AMI. `kcimage upgrade` / `rollback` operate
    here, not on live ASG nodes.

Database rollback is never automatic.

If schema migration has occurred, recovery requires restoring an RDS
snapshot.

------------------------------------------------------------------------

# 11. Service CLI

Provide a single administration command:

kcimage

Minimum commands:

-   install
-   configure
-   build
-   check
-   version
-   start
-   stop
-   restart
-   status
-   logs
-   journal
-   health
-   verify
-   cluster
-   upgrade
-   rollback
-   seal

------------------------------------------------------------------------

# 12. Validation

The installer shall verify:

-   Java
-   systemd
-   SELinux
-   DNS
-   RDS connectivity
-   Keycloak build
-   Ready endpoint
-   Live endpoint
-   Metrics
-   OIDC discovery
-   Cluster state

------------------------------------------------------------------------

# 13. Logging

Use structured logging.

Support:

-   journalctl integration
-   log rotation
-   health diagnostics

------------------------------------------------------------------------

# 14. SELinux

SELinux Enforcing is mandatory.

Toolkit automates:

-   restorecon
-   semanage
-   policy installation (when required)

Never disable SELinux.

------------------------------------------------------------------------

# 15. AMI Lifecycle

The AMI contains:

-   Java
-   Keycloak
-   Scripts
-   Templates
-   Documentation

The AMI never contains:

-   Secrets
-   Passwords
-   Environment-specific values
-   Realm exports

Provide:

kcimage seal

to sanitize an instance before imaging.

------------------------------------------------------------------------

# 16. Testing Strategy

Required:

-   ShellCheck
-   shfmt
-   Bats
-   Installation tests
-   Upgrade tests
-   Cluster tests
-   Rollback tests

Every milestone must add tests.

------------------------------------------------------------------------

# 17. Coding Standards

Use Bash strict mode.

Every script includes:

-   logging
-   input validation
-   cleanup handlers
-   dry-run mode
-   verbose mode

------------------------------------------------------------------------

# 18. Architecture Decision Records

Before implementation, create ADRs for:

-   Directory structure
-   Configuration hierarchy
-   Upgrade strategy
-   Rollback strategy
-   Clustering
-   Logging
-   Testing
-   SELinux
-   AMI strategy

Implementation begins only after ADR approval.

------------------------------------------------------------------------

# 19. Milestones

1.  ADRs
2.  Repository scaffolding
3.  Installer
4.  Configuration
5.  systemd
6.  SELinux
7.  Validation
8.  Cluster support
9.  Upgrade framework
10. Documentation
11. Production hardening

Each milestone must be independently reviewable.

------------------------------------------------------------------------

# 20. Definition of Done

The project is complete when:

-   A new RHEL-family 10 EC2 instance becomes a production-ready
    Keycloak cluster node using one documented command.
-   All lifecycle operations are documented and automated.
-   All scripts are idempotent.
-   The toolkit passes automated tests.
-   Documentation is sufficient for an engineer unfamiliar with the
    project to deploy and operate it.

------------------------------------------------------------------------

# 21. Instructions to Claude Code

You are the lead software architect and senior DevOps engineer.

Treat this blueprint as authoritative.

Do not invent architecture that conflicts with this document.

If requirements are ambiguous: 1. Stop. 2. Explain the ambiguity. 3.
Propose options. 4. Wait for approval.

Do not sacrifice maintainability for speed.

Prefer clarity over cleverness.

Build a production platform, not a demo.
