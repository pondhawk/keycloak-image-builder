#!/usr/bin/env bash
# subcommand: seal — sanitize the model instance for imaging (ADR-0004).
# Removes secrets, environment-specific config, runtime state, and machine
# identity, then runs a neutrality gate that FAILS if anything sensitive
# remains. This is KIB's "prepare for image" step.
#
# In the consolidated layout everything server-side is under /opt/keycloak, so
# there are no /var/lib|/var/log|/var/backups trees and no versioned installs to
# prune. What seal must scrub is: boot-injected secrets/env on tmpfs
# (/run/keycloak), the keycloak-owned runtime data dir (gzip cache, tx logs —
# emptied but kept, owner/label intact), and host identity.
# shellcheck shell=bash

_seal_usage() {
  cat << EOF
Usage: kcimage seal [--check]

Sanitize this instance so it can be imaged into an environment-neutral image,
then run the neutrality gate.

Options:
  --check     Run only the neutrality gate (no changes) — safe to test
  -h, --help  Show this help
EOF
}

# Empty a directory's contents but keep the directory itself (and its owner,
# mode, and SELinux label) — used for the keycloak-owned data/ and tmpfs /run.
_seal_purge() {
  local dir="$1"
  [[ -d "$dir" ]] || return 0
  if is_dry_run; then
    log_info "[dry-run] would purge contents of $dir"
    return 0
  fi
  find "$dir" -mindepth 1 -delete 2> /dev/null || true
}

# Neutrality gate (ADR-0004): fail if any secret / env-specific value remains.
_seal_gate() {
  local conf_dir="$1" problems=0 f
  # Boot-injected secrets/env live on tmpfs; none may survive into the image.
  for f in "$KC_RUN/keycloak.env" "$KC_RUN/secrets.env" "$KC_RUN/bootstrap.env"; do
    if [[ -e "$f" ]]; then
      log_error "gate: sensitive file still present: $f"
      problems=1
    fi
  done
  # Scan the baked config *directives* for secrets/endpoints, skipping comment
  # and blank lines — the neutral keycloak.conf comment header legitimately
  # mentions "secrets"/"endpoints", and a comment must never trip the gate.
  if [[ -d "$conf_dir" ]]; then
    while IFS= read -r -d '' f; do
      if grep -vE '^[[:space:]]*(#|$)' "$f" 2> /dev/null | grep -qiE 'password|secret|://|amazonaws\.com'; then
        log_error "gate: possible secret/endpoint in $f"
        problems=1
      fi
    done < <(find "$conf_dir" -type f -print0)
  fi
  if [[ "$problems" -ne 0 ]]; then
    log_error "seal neutrality gate FAILED — do NOT image this instance"
    return "$EX_CONFIG"
  fi
  log_info "seal neutrality gate passed — safe to image"
}

cmd_seal() {
  local conf_dir="$KC_CONF" check_only=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check)
        check_only=1
        shift
        ;;
      -h | --help)
        _seal_usage
        return 0
        ;;
      *)
        log_error "seal: unknown argument: $1"
        _seal_usage
        return "$EX_USAGE"
        ;;
    esac
  done

  if [[ "$check_only" == "1" ]]; then
    _seal_gate "$conf_dir"
    return $?
  fi

  guard_not_live_node "seal" || return $?
  if ! is_dry_run && [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    log_error "seal must run as root"
    return "$EX_CONFIG"
  fi
  confirm "This will SANITIZE this instance for imaging (remove secrets, env config, runtime state, SSH host keys, machine-id)." || return $?

  log_info "sanitizing instance for imaging"
  # Boot-injected env + secrets (tmpfs)
  _seal_purge "$KC_RUN"
  # Runtime data (gzip cache, tx logs) — empty it, keep the keycloak-owned dir
  _seal_purge "$KC_DATA"
  # Machine identity + host-specific residue (regenerated per instance)
  if is_dry_run; then
    log_info "[dry-run] would truncate /etc/machine-id, remove SSH host keys, scrub cloud-init state + shell history"
  else
    : > /etc/machine-id 2> /dev/null || log_warn "could not truncate /etc/machine-id"
    rm -f /etc/ssh/ssh_host_* 2> /dev/null || true
    if command -v journalctl > /dev/null 2>&1; then
      journalctl --rotate --vacuum-time=1s > /dev/null 2>&1 || true
    fi
    # cloud-init caches the raw launch-template user-data — which carries the DB
    # password — in cleartext under /var/lib/cloud and echoes it into its logs.
    # Both would bake into the image, so scrub them (the same leak class as a
    # secret in keycloak.conf). Explicit rm covers the no-cloud-init case.
    if command -v cloud-init > /dev/null 2>&1; then
      cloud-init clean --logs --seed > /dev/null 2>&1 || log_warn "cloud-init clean failed"
    fi
    rm -rf /var/lib/cloud/instance /var/lib/cloud/instances 2> /dev/null || true
    rm -f /var/log/cloud-init.log /var/log/cloud-init-output.log 2> /dev/null || true
    # Shell history — root's, and the operator who invoked us under sudo, who may
    # have handled live credentials interactively.
    rm -f /root/.bash_history 2> /dev/null || true
    local op_home
    op_home="$(getent passwd "${SUDO_USER:-}" 2> /dev/null | cut -d: -f6)"
    if [[ -n "$op_home" && "$op_home" != "/root" ]]; then
      rm -f "$op_home/.bash_history" 2> /dev/null || true
    fi
  fi

  if is_dry_run; then
    log_info "[dry-run] would run the neutrality gate"
    return 0
  fi
  _seal_gate "$conf_dir"
}
