# KIB Coding Standards

All KIB code is **Bash 5**, orchestration-style. These standards are enforced by
ShellCheck, shfmt, and review.

## Bash strict mode (mandatory)

Every executable script starts with:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
```

- `-E` so `ERR` traps fire in functions/subshells.
- `-e` exit on error, `-u` no unset vars, `-o pipefail` catch pipe failures.

## Every script provides

Per blueprint §17:

- **Logging** — via `lib/log.sh` (`log_info`, `log_warn`, `log_error`,
  `log_debug`). No bare `echo` for diagnostics. Never log secrets (ADR-0008).
- **Input validation** — validate args/env before acting; fail fast with a clear
  message and non-zero exit.
- **Cleanup handlers** — `trap` on `ERR`/`EXIT` to remove temp files and leave a
  safe state.
- **Dry-run mode** — `--dry-run` performs no mutating action; every mutating call
  goes through a helper that respects it. Tested (ADR-0012).
- **Verbose mode** — `--verbose` raises log level to debug.

## Idempotency (blueprint principle 2)

Operations must be safe to re-run: check-then-act, converge to the desired
state, exit 0 if already there. Tested by running twice (ADR-0012).

## Structure

- `scripts/kcimage` — the dispatcher only; no business logic.
- `scripts/subcommands/<cmd>.sh` — one file per subcommand, exposes
  `cmd_<name>()`.
- `lib/*.sh` — sourced helpers (`log`, `common`, `aws`, `db`, `selinux`,
  `systemd`, `validate`). Pure-ish functions, no top-level side effects.

## Style

- `shfmt -i 2 -ci -sr` formatting (2-space indent).
- `snake_case` functions and locals; `local` for every function variable.
- `readonly`/`declare -r` for constants; UPPER_CASE for globals/env.
- Quote all expansions: `"$var"`, `"${arr[@]}"`.
- Prefer `[[ ]]`; use `$(...)` not backticks.
- Functions return status; "return" data via stdout.

## Error handling

- Fail with context: `log_error "…"; exit 1` (or a named exit code).
- Reserve exit codes (e.g. `EX_USAGE=64`, `EX_CONFIG=78`) in `lib/common.sh`.

## Secrets (ADR-0008)

- Never echo/log secret values; no `set -x` around secret handling.
- Secrets live only in tmpfs (`/run/keycloak`), never persistent disk or repo.

## Don't test Keycloak (ADR-0012)

Validate that KIB did its job (install/config/clean/deploy/wiring), not that
Keycloak's auth logic works.
