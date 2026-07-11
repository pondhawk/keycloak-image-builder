#!/usr/bin/env bash
# lib/selinux.sh — SELinux file-context management (ADR-0011).
# shellcheck shell=bash

# selinux_available — SELinux tooling present and not Disabled.
selinux_available() {
  command -v getenforce > /dev/null 2>&1 || return 1
  [[ "$(getenforce 2> /dev/null)" != "Disabled" ]]
}

# _resolve_selinux_fc — echo the KDT fcontext file (repo or installed layout).
_resolve_selinux_fc() {
  local d
  for d in "$KCADMIN_BIN_DIR/../selinux" "$KCADMIN_LIB_DIR/../selinux"; do
    if [[ -f "$d/keycloak.fc" ]]; then
      readlink -f "$d/keycloak.fc"
      return 0
    fi
  done
  return 1
}

# _selinux_add_fcontext <type> <regex> — idempotent add-or-modify.
_selinux_add_fcontext() {
  local setype="$1" regex="$2"
  if semanage fcontext -l 2> /dev/null | grep -qF -- "$regex"; then
    run semanage fcontext -m -t "$setype" "$regex"
  else
    run semanage fcontext -a -t "$setype" "$regex"
  fi
}

# selinux_apply <fc-file> — register fcontexts and relabel paths (idempotent).
selinux_apply() {
  local fc="$1"
  [[ -f "$fc" ]] || {
    log_error "fcontext file not found: $fc"
    return "$EX_CONFIG"
  }
  if ! is_dry_run; then
    require_cmd semanage restorecon || return "$EX_CONFIG"
  fi
  local regex setype root
  # Split on space/tab (the dispatcher sets IFS=\n\t, which would not split columns).
  while IFS=$' \t' read -r regex setype _; do
    [[ -z "$regex" || "$regex" == \#* ]] && continue
    [[ -n "$setype" ]] || continue
    if is_dry_run; then
      log_info "[dry-run] would label $regex as $setype and relabel"
      continue
    fi
    _selinux_add_fcontext "$setype" "$regex" || return "$EX_CONFIG"
    root="${regex%%(*}"
    if [[ -e "$root" ]]; then
      run restorecon -RF "$root" || log_warn "restorecon failed: $root"
    fi
  done < "$fc"
}
