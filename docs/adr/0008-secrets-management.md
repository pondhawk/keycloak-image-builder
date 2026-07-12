# ADR-0008: Node Configuration & Secrets Delivery

- **Status:** Accepted (revised 2026-07-12 — supersedes the AWS Secrets Manager design)
- **Date:** 2026-07-11 (revised 2026-07-12)
- **Deciders:** James Moring (owner), Claude Code (architect)
- **Format:** Nygard ADR (Context · Decision · Consequences)

## Context

The AMI is environment-neutral and carries **no** config or secrets (§15,
ADR-0004). Every ephemeral ASG node must therefore obtain its configuration —
including the DB credentials — at boot, from outside the image. What a node
needs:

- DB connection (`KC_DB_URL`, `KC_DB_USERNAME`, `KC_DB_PASSWORD`), the public
  hostname (`KC_HOSTNAME`), JVM sizing, and — only for an uninitialized DB — a
  bootstrap admin.
- Its own private IP (JGroups bind address), which is per-instance.

An earlier revision of this ADR fetched these from **AWS Secrets Manager** at
boot. That was reconsidered (2026-07-12): for a system whose whole job is to
scale reliably, the secret-fetch is a **brittle chain that must all be right on
every launch** — the AWS CLI v2 present (and it is *not* in the RHEL repos), `jq`
present, a network path to Secrets Manager (VPC endpoint/NAT), a correctly
scoped IAM role, and a well-formed secret. Miss one and the node will not boot.
That is a lot of configuration surface, plus two tooling dependencies, for
marginal benefit **on a single-purpose node** (see threat model below).

## Decision

### Configuration (incl. DB credentials) is delivered via launch-template user-data

Each cluster's launch template carries its config as **`KEY=VALUE` lines using
Keycloak's `KC_*` names** in user-data. `KEY=VALUE` is bash-native (no `jq`) and
maps 1:1 to Keycloak's env vars.

```sh
# required
KC_DB_URL=jdbc:mysql://prod-rds.internal:3306/keycloak
KC_DB_USERNAME=keycloak_app
KC_DB_PASSWORD=<the db password>
KC_HOSTNAME=https://auth.example.com
# optional
JAVA_OPTS_APPEND=-Xms512m -Xmx1024m
# only for an uninitialized DB (usually omitted):
KC_BOOTSTRAP_ADMIN_USERNAME=<user>
KC_BOOTSTRAP_ADMIN_PASSWORD=<pass>
```

Each launch template carries its own block, so "which cluster" is implicit — no
pointer or secret name needed.

### Boot split (unchanged): secrets → tmpfs, the rest → /etc/keycloak

`keycloak-config.service` (root oneshot, ADR-0005) reads IMDSv2 and routes each
key by sensitivity:

| Source / key | Destination |
|--------------|-------------|
| IMDS `local-ipv4` → `KC_CACHE_EMBEDDED_NETWORK_BIND_ADDRESS` | `/etc/keycloak/keycloak.env` |
| user-data `KC_DB_URL`, `KC_HOSTNAME`, `JAVA_OPTS_APPEND`, other `KC_*` | `/etc/keycloak/keycloak.env` |
| user-data `KC_DB_USERNAME`, `KC_DB_PASSWORD`, `KC_BOOTSTRAP_ADMIN_*` | `/run/keycloak/secrets.env` (**tmpfs**, 0640 root:keycloak) |

`keycloak.service` consumes both as `EnvironmentFile=` entries. Secrets on tmpfs
**never hit persistent disk** and cannot be captured into an AMI. `db.vendor` is
*not* here — it is build-time, baked into the per-vendor AMI (ADR-0003).

### No AWS tooling at boot

Boot is: IMDSv2 token → read `local-ipv4` + `user-data` (curl) → parse
`KEY=VALUE` → write two files → start. **No AWS CLI, no `jq`, no Secrets Manager,
no VPC endpoint, no secrets IAM role.** Self-contained, few failure points.

### Threat model — why this is acceptable

Putting the DB password in user-data is a deliberate, bounded trade:

- **Single-purpose node.** The box runs only Keycloak. The only on-box actor that
  can read user-data (via IMDS) is a compromised Keycloak — which would already
  have the DB creds from its own process/session. So user-data adds ~zero on-box
  exposure over the tmpfs approach.
- **The password guards data the reader can already reach.** It protects the
  identity data in RDS; anyone who can reach and query RDS already has that data.
- **Off-box exposure is controlled by IAM.** The one gap — `ec2:DescribeLaunch
  TemplateVersions` is sometimes granted more broadly than RDS access — is closed
  by **restricting launch-template read access via IAM** to the same principals
  who can reach RDS.

Required mitigations (operator-provisioned): **IAM-restricted launch-template
read**, **IMDSv2 required** (tokens + hop limit), and **keep user-data out of
logs** — our systemd oneshot reads user-data directly and never logs it; do
*not* also run that user-data as a cloud-init script (cloud-init can echo
user-data into its logs).

### Rotation

Update the launch template's user-data and cycle the nodes (ASG instance
replacement) — routine under the immutable model. Keycloak reads creds at start,
so a running fleet needs a cycle regardless of the source.

### No secret ever logged

The boot script and `kcimage` never echo secret values (strict mode, no `set -x`
over secret handling; errors list key *names*, not values).

## Consequences

### Positive

- **Fewest moving parts at boot:** no AWS CLI (the non-RHEL-repo bundle), no `jq`,
  no VPC endpoint, no Secrets-Manager IAM, no secret to provision. Boot can't fail
  on any of those.
- Secrets still stay off persistent disk and out of the AMI (tmpfs delivery).
- One place per cluster to set config (the launch template), in Keycloak's own
  `KC_*` names — self-documenting.

### Negative / Trade-offs

- The DB password lives in the launch template (plaintext, IAM-gated). Accepted
  for a single-purpose node with restricted launch-template access; it is the
  crux of this decision and must be a conscious operator choice.
- Less audit than Secrets Manager (no per-read CloudTrail trail on the credential).
- Rotation requires editing the launch template and cycling nodes (cheap under
  ASG, but not a Secrets-Manager rotation).

### Notes

- Boot orchestration and unit wiring → ADR-0005.
- Config layering (secret vs non-secret) → ADR-0002.
- Vendor split (`db.vendor` is build-time) → ADR-0003.
- ADR-0007 Step 4 (rename-swap): rename-swap preserves the endpoint, so the
  user-data `KC_DB_URL` stays valid and needs **no edit**; a true repoint means
  editing the launch template's `KC_DB_URL`.
- **Superseded:** the AWS Secrets Manager approach (single JSON secret per
  cluster + user-data pointer + IAM `GetSecretValue`) — dropped 2026-07-12 for
  the brittleness/dependency reasons in Context. Revisit if a future need
  (tighter audit, broad multi-tenant nodes) outweighs the added surface.
```
