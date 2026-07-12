# ADR-0010: Logging

- **Status:** Accepted
- **Date:** 2026-07-11
- **Deciders:** James Moring (owner), Claude Code (architect)
- **Format:** Nygard ADR (Context · Decision · Consequences)

> **Implementation status (2026-07-12):** on-node JSON logging → journald is
> implemented and works. The **centralized Fluent Bit → CloudWatch** path is
> **deferred to a follow-up feature** and is NOT in v0.1.0 — partly because
> `fluent-bit` is not in the base RHEL repos (it needs the official Fluent Bit
> repo), which should be re-evaluated (e.g. vs. the Amazon CloudWatch agent)
> when it is actually implemented. The orphaned `templates/fluent-bit.conf`
> was removed.

## Context

The blueprint (§13) requires structured logging, journalctl integration, log
rotation, and health diagnostics. The ASG model adds a constraint the blueprint
does not spell out but that dominates logging design:

- **Nodes are ephemeral.** When the ASG scales in or replaces an unhealthy
  instance, that instance's local logs are **gone**. Any log that exists only on
  the node is unavailable exactly when you need it — to investigate why a node
  was replaced. A "supportable, production-quality" platform (§1) therefore
  needs logs to survive the node.

Other decisions constrain this ADR: the systemd service already sends
stdout/stderr to journald (ADR-0005); log configuration lives in the neutral
`keycloak.conf` (ADR-0002); secrets must never be logged (ADR-0008).

## Decision

### Format: structured JSON to the console

Keycloak logs in **structured JSON** to the console
(`log-console-output=json`, `log-level` per category, set in `keycloak.conf`).
JSON makes logs machine-parseable for centralized querying and keeps a single
format across all nodes. The JSON output supports a `default` or **`ecs`**
(Elastic Common Schema) shape; `ecs` is preferred when centralized logging is
enabled, for cleaner field mapping. (Exact option names pinned at implementation.)

### On-node: console → journald (always)

stdout/stderr is captured by **journald** (`journalctl -u keycloak`), per
ADR-0005. `kcimage logs` / `kcimage journal` wrap `journalctl` and offer a
pretty-printed view of the JSON for humans. **No file appender / no logrotate** —
console-only keeps the on-node path simple and avoids managing rotating files.

### Centralized: Fluent Bit → CloudWatch Logs (opt-in)

Because nodes are ephemeral, journald is only a **short local buffer**. When
centralized logging is enabled, the AMI runs **Fluent Bit** (installed from the
official `fluent-bit` RPM) with a **systemd/journald input** and a
**`cloudwatch_logs` output**, shipping to a per-environment **log group**, one
**log stream per instance-id**:

```
Keycloak → console (JSON) → journald → Fluent Bit → CloudWatch Logs
```

Reading journald directly keeps the no-file design — no log file, no
`logrotate`, no writing to disk only to read it back. (Keycloak has no native
cloud sink, and the CloudWatch unified agent only tails *files*, not journald —
which is why a journald-native shipper is used.)

- **Opt-in.** Disabled by default; enabling it starts the Fluent Bit unit. With
  it off, the on-node journald path still serves `kcimage logs`.
- KIB ships the Fluent Bit configuration; the **operator provisions** the log
  group, its retention, and the IAM permission (`logs:CreateLogStream`,
  `logs:PutLogEvents`) on the instance role — infrastructure KIB documents but
  does not create.
- Strongly recommended for any real cluster (cattle nodes make local-only logs
  nearly useless), but explicitly optional.

### Rotation

- **On-node:** journald size/time caps (`SystemMaxUse`, `MaxRetentionSec`) bound
  local disk — it is only a buffer that Fluent Bit ships from.
- **Centralized:** retention is a property of the CloudWatch log group, set by
  the operator. No file-based rotation exists to manage.

### Correlation and health diagnostics

- Log context carries **node identity** (instance-id / cluster node address) so
  multi-node logs in CloudWatch are attributable to a specific instance.
- `kcimage health` / `verify` aggregate a diagnostic summary — `/health/ready`,
  `/health/live`, metrics, DB connectivity, cluster size (ADR-0009) — and
  `kcimage logs --since ...` aids triage. Health diagnostics and logs share the
  node identity fields for correlation.

### Scope boundary: server logs vs. Keycloak events

This ADR covers **operational/server logs**. Keycloak's own **login/admin
events** (a security-audit concern) are realm configuration, stored in the DB or
emitted via an event listener SPI. KIB enables sensible server logging and notes
events as realm-level configuration, not part of the core server-logging path.

### Never log secrets

Per ADR-0008, secret values never appear in logs. JSON logging must not emit
secret-bearing environment; scripts avoid `set -x` around secret handling and
redact diagnostics.

## Consequences

### Positive

- Logs survive ephemeral nodes: a scaled-in or replaced instance's logs remain
  in CloudWatch, which is essential for diagnosing ASG churn.
- Structured JSON is queryable centrally and uniform across nodes; `kcimage`
  pretty-prints it for humans on-node.
- Console → journald → Fluent Bit → CloudWatch removes file-rotation complexity
  entirely (no file appender, no disk round-trip).
- Node-identity correlation ties logs, health, and cluster state together.

### Negative / Trade-offs

- CloudWatch Logs is an added AWS dependency with its own cost and IAM surface.
  Justified by the ephemeral-node reality, but it is the one place this design
  reaches beyond the node.
- Raw JSON in `journalctl` is less readable than plain text; mitigated by
  `kcimage logs` formatting, but direct `journalctl` users see JSON lines.
- Centralized logging depends on operator-provisioned infrastructure (log group
  + IAM); if it is missing, only the short-lived on-node buffer exists.
- Fluent Bit is an additional on-node daemon with its own config format, and
  reading journald under SELinux Enforcing needs correct labeling (ADR-0011).

### Notes

- systemd journald wiring → ADR-0005.
- Log config placement in `keycloak.conf` → ADR-0002.
- Health/metrics endpoints and cluster checks → ADR-0009.
- Secret redaction → ADR-0008.
- Fluent Bit SELinux labeling / policy → ADR-0011.
