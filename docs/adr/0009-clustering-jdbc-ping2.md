# ADR-0009: Clustering (JDBC_PING2)

- **Status:** Accepted
- **Date:** 2026-07-11
- **Deciders:** James Moring (owner), Claude Code (architect)
- **Format:** Nygard ADR (Context · Decision · Consequences)

## Context

KIB runs a multi-node Keycloak cluster behind an AWS ALB, in private subnets,
with nodes launched and terminated dynamically by an ASG. Nodes must discover
each other without multicast (unavailable in AWS), form a JGroups/Infinispan
cluster, and tolerate constant membership churn.

The blueprint fixes the approach (§9): JDBC_PING2 discovery, shared RDS, ALB,
private subnets, self-referencing security-group rules, health and metrics
enabled. Validation must verify membership, size, health, metrics, OIDC
discovery, and Admin Console.

Verified against the Keycloak 26.x docs (2026-07-11):

- Keycloak 26 has a **built-in `jdbc-ping` cache stack** (JDBC_PING2), and it is
  the **default** when distributed caches are enabled — no custom JGroups XML is
  required for the standard case (`--cache-stack=jdbc-ping`).
- Node-to-node transport is **TCP 7800** (`cache-embedded-network-bind-port`);
  failure detection uses **57800** (bind port + 50000 offset).
- Keycloak 26 stores user/client sessions in the **database** (persistent
  sessions) by default, so losing a node does not lose sessions.

## Decision

### Discovery: the default `jdbc-ping` stack against the shared datasource

Distributed caches are enabled (`cache=ispn`) with `cache-stack=jdbc-ping`
(the 26.x default; set explicitly for clarity). JDBC_PING2 uses the **same
Keycloak datasource** — nodes register their address in a discovery table in
the shared RDS and read it to find peers. No separate discovery service, no
custom cache config file.

### Discovery table lives in the Keycloak schema

The discovery table is created/managed within the Keycloak schema by the
`jdbc-ping` stack. The Keycloak DB user already holds DDL rights (Liquibase
creates/alters Keycloak's own tables), so **no extra privilege** is needed for
table initialization. The per-vendor **DDL dialect** difference (Postgres vs
MySQL) is handled by the stack and is the clustering fork point noted in
ADR-0003. (Exact table name and init behavior confirmed at implementation.)

### Network binding to the instance's private IP

Each node binds JGroups to its **private IP** —
`cache-embedded-network-bind-address` set at boot from instance metadata, port
7800. Peers connect to the registered address over 7800, with failure detection
on 57800. Binding to the reachable private address (not loopback) is essential
or peers cannot connect.

### Security group: self-referencing intra-cluster rule

Cluster nodes sit in private subnets under a security group with a
**self-referencing** inbound rule allowing **TCP 7800 and 57800 from the group
itself**. This is the infrastructure contract KIB **documents and validates**
but does not create (consistent with "toolkit never creates infrastructure").
The ALB only front-ends HTTP(S); it is **not** part of cluster traffic.

### Health, metrics, TLS, and the ALB

**TLS terminates at the ALB** using an **ACM** certificate (auto-renewed — no
certificate management on instances). The ALB forwards **plain HTTP** to targets
inside the VPC; instances **do not** terminate TLS and serve HTTP only (default
8080) with `proxy-headers=xforwarded` so Keycloak still builds correct
`https://` URLs from the ALB's `X-Forwarded-*` headers. Health and metrics are
enabled on the management port (9000), which the ALB target group health-checks
at `/health/ready`. Cluster traffic (7800/57800) is direct node-to-node and
never traverses the ALB.

### Churn tolerance and stale members

ASG scale-in and unhealthy-instance replacement mean nodes leave, sometimes
ungracefully. JGroups failure detection (57800) and view-change handling reap
dead members and their discovery rows; an ungracefully terminated node may leave
a **brief** stale entry until detection times out. This is acceptable and
self-healing. Persistent user/client sessions being in the DB means node loss
does not drop sessions — a key property for a churning ASG.

### Validation (`kcimage cluster`)

Confirms the §9/§12 cluster checks: actual **cluster membership and size**,
`/health/ready` + `/health/live`, the metrics endpoint, OIDC discovery, and
Admin Console availability. **A cluster size of 1 is valid** during
scale-from-zero and during the upgrade smoke test (ADR-0006) — not a failure.
`kcimage` flags only a *persistent* mismatch between healthy ASG capacity and
observed cluster size.

## Consequences

### Positive

- Using the built-in default stack against the existing datasource makes
  clustering nearly configuration-free: no extra service, no custom XML, no
  extra DB privileges.
- DB-backed discovery and DB-backed sessions make the cluster naturally
  resilient to ASG churn.
- The only real infrastructure requirements — private-IP binding and the
  self-referencing SG rule on 7800/57800 — are few, explicit, and validatable.

### Negative / Trade-offs

- Discovery depends on the shared RDS; if the DB is unreachable, both persistence
  *and* discovery fail together (though a Keycloak node cannot function without
  its DB anyway, so this concentrates rather than adds risk).
- Ungraceful termination leaves short-lived stale discovery rows; harmless but
  visible, and operators must not mistake them for a real membership problem.
- A network partition where nodes can still reach the DB but not each other can
  cause a JGroups split; low probability within one VPC, but not zero.
- The self-referencing SG rule on the JGroups ports is the single most common
  AWS clustering misconfiguration; it must be documented prominently and checked
  by validation.

### Notes

- Per-vendor DDL dialect → ADR-0003.
- Boot-time bind-address rendering → ADR-0005 config oneshot.
- Health/metrics specifics and log correlation → ADR-0010.
- Size-1 acceptance and smoke test → ADR-0006.
