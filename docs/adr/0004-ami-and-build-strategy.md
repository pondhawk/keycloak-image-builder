# ADR-0004: AMI & Build Strategy

- **Status:** Accepted
- **Date:** 2026-07-11
- **Deciders:** James Moring (owner), Claude Code (architect)
- **Format:** Nygard ADR (Context · Decision · Consequences)

## Context

KIB builds a golden model instance that is imaged into an AMI and consumed by
an AWS Auto Scaling Group. Three earlier decisions shape this ADR:

- **Build at bake (Option A).** `kc.sh build` runs during image preparation,
  not at instance boot, so ASG scale-out is fast (ADR-0002 rationale).
- **Per-vendor AMIs.** The database vendor is a Keycloak build-time option, so
  each AMI is baked for exactly one `db.vendor` (ADR-0003). Drivers for both
  Postgres and MySQL are bundled — no per-vendor driver step (ADR-0003,
  verified against 26.x docs).
- **Environment-neutral AMI (§15).** The image must carry no secrets, no
  hostname, no RDS endpoint, no realm exports, and no cluster identity.

Keycloak's build model matters here: `kc.sh build` produces an *augmented,
optimized* server for a fixed set of build-time options; a node then starts
with `kc.sh start --optimized` to skip re-augmentation. This is what makes
build-at-bake worthwhile — the boot path does no build work.

The blueprint (§15) already lists what the AMI must and must not contain and
mandates `kcimage seal`. This ADR pins the build sequence, the two-AMI
lineage, the exact neutrality contract, and how AMIs are tagged and retained so
the immutable upgrade/rollback model (ADR-0006/0007) can rely on them.

## Decision

### 1. Build happens on the golden instance, once per vendor

The bake sequence, driven by `kcimage` on the golden instance:

1. `install` — lay down Java, the Keycloak version, scripts, units, policy.
2. `configure` — render the **neutral** `keycloak.conf` (build-time options,
   including `db=<vendor>`); no environment-specific values.
3. deploy custom provider JARs from `~/keycloak-custom-providers` into `/opt/keycloak/providers`.
4. `build` — run `kc.sh build` for the selected `db.vendor`, producing the
   optimized server.
5. `verify` — validate the built server (§12 checks that do not require a live
   environment: Java, build success, SELinux contexts, unit files).
6. `seal` — sanitize to the neutral contract (below).
7. image — create the AMI **manually in the AWS Console** (select the golden
   instance → Actions → Image and templates → Create image) from the sanitized
   instance.

OS patching: the bake also applies a full `dnf -y update` on the model instance
before step 6 (`seal`), so every AMI is fully patched at build time
(ADR-0013).

### 2. Two AMI lineages, one codebase

Each release produces up to two AMIs from the identical procedure and codebase,
differing only in `db.vendor`:

- `kdt-keycloak-<kc-version>-postgres-<kdt-version>`
- `kdt-keycloak-<kc-version>-mysql-<kdt-version>`

Both share the ADR-0001 directory layout. If a deployment only needs MySQL,
only the MySQL AMI need be baked — but CI still exercises both (ADR-0003).

### 3. Neutrality contract (what `seal` guarantees)

**The AMI contains:** OpenJDK 21; the single Keycloak install at `/opt/keycloak`
(`KEYCLOAK_HOME`); the built/optimized server; the neutral
`conf/keycloak.conf` baked inside it; `kcimage` + scripts; systemd units;
SELinux policy; templates; docs.

**The AMI never contains, and `seal` removes/resets:**

| Removed / reset | Why |
|---|---|
| `/run/keycloak/keycloak.env`, `secrets.env`, `bootstrap.env` (tmpfs) | environment-specific / secret; injected at boot |
| any cached secret material | no secrets in image |
| `/opt/keycloak/data` contents (gzip cache, tx logs) — dir kept, emptied | runtime state, not neutral; regenerated on boot |
| Keycloak journal entries | logs are instance history |
| realm exports, if any | forbidden by §15 |
| `/etc/machine-id` (truncated) | force per-instance regeneration → unique node identity for clustering |
| SSH host keys | regenerated per instance |
| cloud-init instance state/logs, shell history, `/tmp` | prevent identity/secret bleed |

`seal` is **idempotent** and ends with a **neutrality gate**: it scans for
any residual secret or environment-specific value and **fails the bake** if one
is found. A leaked secret in a published AMI is the highest-severity failure
this toolkit can produce, so the gate is mandatory, not advisory.

### 4. Boot path does no build

Because the server is pre-built, ASG nodes start with `kc.sh start
--optimized` (wired in ADR-0005). First boot only: fetch secrets, render
`keycloak.env`, run one-shot init if needed, start, join cluster, pass ALB
health check.

### 5. Naming, provenance, retention

AMIs are created manually in the AWS Console. Give each a descriptive **name**
following the lineage convention (§2) and a small set of **tags** —
`keycloak-version`, `db-vendor`, `kdt-version`, `build-date` — entered in the
console at create time. That is enough to make each AMI a traceable, immutable
artifact that a launch template references and that rollback (ADR-0007) selects
by re-pointing to the prior AMI.

Retention is manual: keep the last few AMIs per (vendor, version) line as
rollback targets and deregister older ones (and delete their snapshots) by hand
when no longer needed. No automated prune is required at this scale.

## Consequences

### Positive

- Fast, predictable ASG scale-out: no build work at boot.
- AMIs are immutable, tagged, and reproducible, giving the upgrade and rollback
  models a concrete artifact to move between (ADR-0006/0007).
- Neutrality is enforced by a gate, not by discipline — the same property that
  makes ADR-0002 auditable.
- Drivers being bundled keeps the two lineages identical except for one build
  flag, minimizing per-vendor divergence.

### Negative / Trade-offs

- Two AMIs per release to build, test, publish, and lifecycle, in lockstep.
- `seal` correctness is security-critical; its neutrality gate must be
  thoroughly tested (a false "clean" leaks secrets, a false "dirty" blocks
  releases). This is the single most important test target in the AMI path.
- AMI/snapshot sprawl has real storage cost; old images are cleaned up by hand,
  and deleting too aggressively removes rollback targets.
- A build-time option accidentally set to an environment-specific value would
  bake non-neutral config; the ADR-0002 classification gate must run *before*
  imaging to catch this.

### Notes

- Imaging is performed manually in the AWS Console; KIB owns only the
  on-instance contract (install→configure→build→verify→seal).
- `--optimized` start wiring and unit ordering → ADR-0005.
- Rollback-by-AMI-tag → ADR-0007; instance-refresh upgrade → ADR-0006.
- SELinux relabel/verify during bake → ADR-0011.
