#!/usr/bin/env bash
# subcommand: ami-clean — sanitize the model instance for imaging (ADR-0004).
# Removes secrets, environment-specific config, runtime state, and machine
# identity, then runs a neutrality gate that FAILS if anything sensitive
# remains. This is KDT's "prepare for image" step.
# shellcheck shell=bash

_amiclean_usage() {
  cat << EOF
Usage: kcadmin ami-clean [--etc-dir <dir>] [--check]

Sanitize this instance so it can be imaged into an environment-neutral AMI, then
run the neutrality gate.

Options:
  --etc-dir <dir>   Config dir (default: /etc/keycloak)
  --opt-dir <dir>   Keycloak install root (default: /opt/keycloak)
  --check           Run only the neutrality gate (no changes) — safe to test
  -h, --help        Show this help
EOF
}

# Remove every Keycloak install except the one 'current' points at. Rollback is
# via the previous AMI, so old on-instance installs are pure AMI bloat.
_amiclean_prune_versions() {
  local opt_dir="$1" keep="" dir base
  local current="$opt_dir/current"
  if [[ -L "$current" ]]; then
    keep="$(readlink "$current")"
    keep="${keep##*/}"
  fi
  if [[ -z "$keep" ]]; then
    log_warn "no 'current' symlink in $opt_dir; skipping old-version prune"
    return 0
  fi
  shopt -s nullglob
  local dirs=("$opt_dir"/keycloak-*)
  shopt -u nullglob
  for dir in "${dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    base="${dir##*/}"
    [[ "$base" == "$keep" ]] && continue
    if is_dry_run; then
      log_info "[dry-run] would remove old install: $dir"
    else
      log_info "removing old install: $dir"
      rm -rf "$dir"
    fi
  done
}

_amiclean_rm() {
  local path="$1"
  [[ -e "$path" ]] || return 0
  run rm -f "$path"
}

_amiclean_purge() {
  local dir="$1"
  [[ -d "$dir" ]] || return 0
  if is_dry_run; then
    log_info "[dry-run] would purge contents of $dir"
    return 0
  fi
  find "$dir" -mindepth 1 -delete 2> /dev/null || true
}

# Neutrality gate (ADR-0004): fail if any secret / env-specific value remains.
_amiclean_gate() {
  local etc_dir="$1" problems=0 f
  for f in "$etc_dir/keycloak.env" "$etc_dir/bootstrap.env" /run/keycloak/secrets.env; do
    if [[ -e "$f" ]]; then
      log_error "gate: sensitive file still present: $f"
      problems=1
    fi
  done
  if [[ -d "$etc_dir" ]] && grep -rqiE 'password|secret|amazonaws\.com' "$etc_dir" 2> /dev/null; then
    log_error "gate: possible secret/endpoint under $etc_dir"
    problems=1
  fi
  if [[ "$problems" -ne 0 ]]; then
    log_error "ami-clean neutrality gate FAILED — do NOT image this instance"
    return "$EX_CONFIG"
  fi
  log_info "ami-clean neutrality gate passed — safe to image"
}

cmd_ami_clean() {
  local etc_dir="$KC_ETC" opt_dir="$KC_OPT" check_only=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --etc-dir)
        etc_dir="${2:-}"
        shift 2
        ;;
      --opt-dir)
        opt_dir="${2:-}"
        shift 2
        ;;
      --check)
        check_only=1
        shift
        ;;
      -h | --help)
        _amiclean_usage
        return 0
        ;;
      *)
        log_error "ami-clean: unknown argument: $1"
        _amiclean_usage
        return "$EX_USAGE"
        ;;
    esac
  done

  if [[ "$check_only" == "1" ]]; then
    _amiclean_gate "$etc_dir"
    return $?
  fi

  if ! is_dry_run && [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    log_error "ami-clean must run as root"
    return "$EX_CONFIG"
  fi

  log_info "sanitizing instance for imaging"
  # Environment-specific config + secrets
  _amiclean_rm "$etc_dir/keycloak.env"
  _amiclean_rm "$etc_dir/bootstrap.env"
  _amiclean_purge /run/keycloak
  # Runtime state
  _amiclean_purge "$KC_VAR_LOG"
  _amiclean_purge "$KC_VAR_BACKUPS"
  _amiclean_purge "$KC_VAR_LIB"
  # Old Keycloak versions (keep only 'current')
  _amiclean_prune_versions "$opt_dir"
  # Machine identity (regenerated per instance)
  if is_dry_run; then
    log_info "[dry-run] would truncate /etc/machine-id and remove SSH host keys"
  else
    : > /etc/machine-id 2> /dev/null || log_warn "could not truncate /etc/machine-id"
    rm -f /etc/ssh/ssh_host_* 2> /dev/null || true
    if command -v journalctl > /dev/null 2>&1; then
      journalctl --rotate --vacuum-time=1s > /dev/null 2>&1 || true
    fi
    rm -f /root/.bash_history 2> /dev/null || true
  fi

  if is_dry_run; then
    log_info "[dry-run] would run the neutrality gate"
    return 0
  fi
  _amiclean_gate "$etc_dir"
}
