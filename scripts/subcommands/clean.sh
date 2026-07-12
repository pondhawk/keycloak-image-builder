#!/usr/bin/env bash
# subcommand: clean — remove everything `install` set up, returning the model
# instance to a pristine state ready for another install. Mostly for testing.
# Inverts `install`, NOT `bootstrap`: it keeps the toolkit (kcimage), OpenJDK
# (unless --purge-java), and your ~/keycloak-custom-providers.
# Idempotent, dry-run aware. Confirm cleanliness with: kcimage clean --dry-run
# shellcheck shell=bash

_clean_usage() {
  cat << EOF
Usage: kcimage clean [--purge-java]

Remove the KIB install (Keycloak, config, state, units, boot script, service
user, SELinux rules). Keeps the toolkit, OpenJDK, and ~/keycloak-custom-providers.
Prompts for confirmation before removing anything (no bypass flag by design).

Options:
  --purge-java   Also remove OpenJDK (dnf remove); off by default
  -h, --help     Show this help

Preview / confirm a torn-down state with:  kcimage --dry-run clean
EOF
}

# Remove a path if present; count it. run() handles dry-run logging.
_clean_path() {
  local p="$1"
  [[ -e "$p" || -L "$p" ]] || return 0
  run rm -rf "$p"
  CLEAN_N=$((CLEAN_N + 1))
}

_clean_units() {
  local u removed=0
  for u in keycloak.service keycloak-config.service; do
    [[ -f "$KC_SYSTEMD_DIR/$u" ]] || continue
    run systemctl disable --now "$u" 2> /dev/null || true
    run rm -f "$KC_SYSTEMD_DIR/$u"
    CLEAN_N=$((CLEAN_N + 1))
    removed=1
  done
  if [[ "$removed" == "1" ]] && ! is_dry_run; then
    systemctl daemon-reload 2> /dev/null || true
  fi
}

_clean_selinux() {
  local fc regex setype
  fc="$(_resolve_selinux_fc)" || return 0
  if ! is_dry_run; then
    if ! selinux_available || ! command -v semanage > /dev/null 2>&1; then
      log_warn "SELinux tooling absent; skipping fcontext rule removal"
      return 0
    fi
  fi
  while IFS=$' \t' read -r regex setype _; do
    [[ -z "$regex" || "$regex" == \#* ]] && continue
    [[ -n "$setype" ]] || continue
    if is_dry_run; then
      log_info "[dry-run] would remove fcontext rule: $regex"
    else
      run semanage fcontext -d "$regex" 2> /dev/null || true
    fi
  done < "$fc"
}

_clean_user() {
  if getent passwd "$KC_USER" > /dev/null 2>&1; then
    run userdel "$KC_USER" 2> /dev/null || log_warn "could not remove user $KC_USER"
    CLEAN_N=$((CLEAN_N + 1))
  fi
  if getent group "$KC_GROUP" > /dev/null 2>&1; then
    run groupdel "$KC_GROUP" 2> /dev/null || log_warn "could not remove group $KC_GROUP"
  fi
}

_clean_java() {
  local java_pkg="$1"
  command -v java > /dev/null 2>&1 || return 0
  log_info "removing $java_pkg"
  run dnf remove -y "$java_pkg" || log_warn "could not remove $java_pkg"
}

cmd_clean() {
  local purge_java=0
  local java_pkg="java-${KIB_JAVA_MAJOR}-openjdk-headless"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --purge-java)
        purge_java=1
        shift
        ;;
      -h | --help)
        _clean_usage
        return 0
        ;;
      *)
        log_error "clean: unknown argument: $1"
        _clean_usage
        return "$EX_USAGE"
        ;;
    esac
  done

  if ! is_dry_run && [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    log_error "clean must run as root"
    return "$EX_CONFIG"
  fi
  confirm "This will REMOVE the KIB install (Keycloak, config, state, units, service user, SELinux rules)." || return $?

  CLEAN_N=0
  log_info "cleaning KIB install (keeps: toolkit, OpenJDK, ~/keycloak-custom-providers)"
  _clean_units
  _clean_path "$KC_BOOT_DIR"
  _clean_path "$KC_OPT"
  _clean_path "$KC_ETC"
  _clean_path "$KC_VAR_LIB"
  _clean_path "$KC_VAR_LOG"
  _clean_path "$KC_VAR_BACKUPS"
  _clean_path "$KC_RUN"
  _clean_selinux
  _clean_user
  [[ "$purge_java" == "1" ]] && _clean_java "$java_pkg"

  if [[ "$CLEAN_N" -eq 0 ]]; then
    log_info "already clean: nothing to remove"
  else
    log_info "clean complete: $CLEAN_N item(s) removed"
  fi
}
