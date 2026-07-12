# KIB Project Rules

Operating rules for building KIB (blueprint §21).

1. **Architecture before code.** No implementation that conflicts with an
   Accepted ADR. To change direction, write or supersede an ADR first.
2. **Stop on ambiguity.** If requirements are unclear: stop, explain the
   ambiguity, propose options, wait for approval. Do not guess.
3. **Idempotent, fail-safe, reversible.** Never overwrite a working install;
   converge; leave a safe state on failure.
4. **Environment-neutral AMI is sacred.** No secrets, hostnames, endpoints, or
   realm data in the image. The `seal` neutrality gate must pass.
5. **Never disable SELinux.** Enforcing always; fix via contexts/policy.
6. **Never weaken secret handling.** Secrets only via user-data → tmpfs;
   never on persistent disk, in the AMI, in logs, or in git.
7. **Every milestone adds validation.** Extend `kcimage verify` / neutrality /
   smoke checks with each milestone (ADR-0012).
8. **Prefer clarity over cleverness.** Maintainability over speed.
9. **Both DB engines stay first-class.** Postgres default, MySQL co-equal in
   tests (ADR-0003).
10. **Don't test Keycloak.** Validate KIB's own work only (ADR-0012).
