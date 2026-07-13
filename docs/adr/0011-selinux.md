# ADR-0011: SELinux

- **Status:** Accepted
- **Date:** 2026-07-11
- **Deciders:** James Moring (owner), Claude Code (architect)
- **Format:** Nygard ADR (Context · Decision · Consequences)

## Context

SELinux **Enforcing is mandatory** and must never be disabled (blueprint §3,
§14). The toolkit automates `restorecon`, `semanage`, and policy installation
"when required." SELinux is KIB's primary mandatory-access control; systemd
sandboxing is secondary defense-in-depth (ADR-0005).

KIB installs Keycloak and its data into **non-standard paths** (ADR-0001), which
means their SELinux labels are not what stock policy expects and must be managed
explicitly. The surfaces that need SELinux attention:

- Files: `/opt/keycloak` (the whole install, `KEYCLOAK_HOME`), its `data/`
  subdir (keycloak-owned runtime state), and `/run/keycloak` (tmpfs env+secrets,
  ADR-0008). There is no `/etc/keycloak` and no `/var/lib|log|backups/keycloak`:
  everything server-side lives under `/opt/keycloak` (ADR-0001). Custom provider
  JARs live in a user home (`~/keycloak-custom-providers`, ADR-0001) and inherit
  its default `user_home_t` label — read only at deploy-time, so no dedicated
  rule is needed.
- Ports: HTTP 8080, management 9000, JGroups 7800 / 57800 (ADR-0009).
- Fluent Bit reading journald and sending to CloudWatch (ADR-0010).
- **No TLS material** on instances (TLS terminates at the ALB), so there are no
  private keys or keystores to label or protect — a simplification.

The central design tension: a **bespoke, tightly-confined `keycloak_t` domain**
is the gold standard but a large, ongoing policy-maintenance burden — at odds
with the project's simplicity goal and §14's "policy **when required**."

## Decision

### 1. Enforcing is a hard invariant

`getenforce` must report **Enforcing** on every node. `kcimage check`/`verify`
assert this and **fail** otherwise. KIB never sets Permissive and never disables
SELinux — problems are fixed with contexts and policy, not by weakening SELinux.

### 2. Pragmatic domain strategy: manage contexts, don't build a bespoke domain up front

Keycloak and Fluent Bit run in the **default systemd service domain** (typically
`unconfined_service_t` under the targeted policy; exact type confirmed in
testing) — **not** a hand-written `keycloak_t` domain. The system is fully
Enforcing and file contexts are managed explicitly; what we do *not* do up front
is invest in a bespoke confinement domain. A custom policy module is introduced
**only when a concrete denial or a specific hardening requirement demands it**
(§14's "when required"). This satisfies the Enforcing mandate at low complexity.

### 3. Explicit, persistent file contexts

KIB declares file-context rules with `semanage fcontext -a` and applies them with
`restorecon -R` after install, after config rendering, and after deploying
custom assets. Because the rules are registered with `semanage`, labels are
correct and **survive a full relabel**.

| Path | Intended context (indicative) | Access |
|------|------------------------------|--------|
| `/opt/keycloak` | `usr_t` | read/execute (immutable install) |
| `/opt/keycloak/bin` | `bin_t` | read/execute |
| `/opt/keycloak/data` | `var_lib_t` | **read/write** — Keycloak's runtime data (gzip cache, tx logs); written in place by the service user |
| `/run/keycloak` (tmpfs) | runtime dir context | read/write |

(Exact type labels are validated on RHEL-family 10 during implementation.)

### 4. tmpfs `/run/keycloak` labeled at boot

Because `/run` is tmpfs and recreated each boot, `/run/keycloak` is created and
labeled per boot via systemd `RuntimeDirectory=keycloak` (correct owner/mode and
context), so secret delivery (ADR-0008) lands with the right label without a
persistent fcontext rule.

### 5. Port labeling deferred (needed only under confinement)

The default service domain does not require port labeling. **If** a confined
`keycloak_t` is later adopted, `semanage port` rules for **7800** and **57800**
(JGroups) are added, and 8080/9000 verified against existing port types. Until
then, no port labeling is done.

### 6. Denial-driven policy workflow

During golden-instance build and testing, KIB exercises representative
operations (start, cluster join, upgrade, Fluent Bit shipping) and inspects the
audit log (`ausearch -m AVC`). A **legitimate** denial is turned into a
**minimal** policy module (`audit2allow`), reviewed, and shipped under
`selinux/` in the repo — never a blanket allow, never Permissive. The AMI thus
bakes any required module plus correct labels.

### 7. Validation

`kcimage` SELinux checks: `getenforce == Enforcing`; expected `semanage
fcontext` rules present; labels on KIB paths correct; **no unexpected AVC
denials** for Keycloak or Fluent Bit in the recent audit log.

## Consequences

### Positive

- Meets the Enforcing mandate with **minimal policy-maintenance burden** —
  explicit contexts, not a bespoke domain to maintain across Keycloak versions.
- `semanage`-registered fcontext rules are robust: correct after copies, reboots,
  and full relabels, and captured in the AMI's filesystem labels.
- No TLS key material on nodes removes a whole class of sensitive-file labeling.
- Denial-driven policy keeps any shipped module small and justified.

### Negative / Trade-offs

- The Keycloak service runs in a **permissive default domain**, not a tightly
  confined one. SELinux still enforces system-wide and protects file contexts,
  but the service itself is not sandboxed by a bespoke domain — a future
  requirement for strict confinement is real additional work (a `keycloak_t`
  module, port labels, booleans).
- Fluent Bit reading journald and reaching CloudWatch may surface denials
  needing a small module; must be exercised during bake, not discovered in prod.
- Label correctness in the AMI depends on `restorecon` running at the right bake
  steps; a missed relabel can cause boot/start failures that look like app bugs.

### Notes

- systemd `RuntimeDirectory` and service domain → ADR-0005.
- tmpfs secret path → ADR-0008.
- Ports and cluster surfaces → ADR-0009.
- Fluent Bit → ADR-0010.
- Policy modules, if any, live in `selinux/` (ADR-0001 repo layout).
