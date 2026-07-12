#!/usr/bin/env bash
# lib/common.sh — shared constants and helpers. Sourced, never executed.
# shellcheck shell=bash
# The constants and mode flags below are this library's public API, consumed by
# the dispatcher and subcommand files; SC2034 (assigned-but-unused within this
# single file) is expected and intentional here.
# shellcheck disable=SC2034

# --- Global mode flags (set by the dispatcher) ---
: "${DRY_RUN:=0}"
: "${VERBOSE:=0}"

# --- Reserved exit codes ---
readonly EX_OK=0
readonly EX_USAGE=64         # command-line usage error
readonly EX_CONFIG=78        # configuration error
readonly EX_UNIMPLEMENTED=69 # planned but not yet implemented

# --- Baseline versions (ADR-0003/0004) ---
readonly KDT_KEYCLOAK_BASELINE="26"
readonly KDT_JAVA_MAJOR="21"

# --- Filesystem layout (ADR-0001) ---
readonly KC_OPT="/opt/keycloak"
readonly KC_CURRENT="/opt/keycloak/current"
readonly KC_CUSTOM="/opt/keycloak-custom"
readonly KC_ETC="/etc/keycloak"
readonly KC_VAR_LIB="/var/lib/keycloak"
readonly KC_VAR_LOG="/var/log/keycloak"
readonly KC_VAR_BACKUPS="/var/backups/keycloak"
readonly KC_USER="keycloak"
readonly KC_GROUP="keycloak"
readonly KC_SYSTEMD_DIR="/usr/lib/systemd/system"
readonly KC_BOOT_DIR="/usr/local/lib/keycloak"

# --- Keycloak distribution source ---
readonly KEYCLOAK_DOWNLOAD_BASE="https://github.com/keycloak/keycloak/releases/download"

# is_dry_run — true when --dry-run is active.
is_dry_run() { [[ "${DRY_RUN:-0}" == "1" ]]; }

# join_sp <items...> — join arguments with single spaces (the dispatcher sets
# IFS=\n\t, so "${arr[*]}" would otherwise join with newlines in messages).
join_sp() {
  local IFS=' '
  printf '%s' "$*"
}

# run <cmd...> — execute a mutating command, respecting --dry-run.
# Use for every side-effecting call so dry-run is honoured (coding standards).
run() {
  local IFS=' ' # join $* with spaces in log messages (dispatcher sets IFS=\n\t)
  if is_dry_run; then
    log_info "[dry-run] $*"
    return 0
  fi
  log_debug "exec: $*"
  "$@"
}

# require_cmd <name...> — fail fast if a required external tool is missing.
require_cmd() {
  local missing=0 c
  for c in "$@"; do
    command -v "$c" > /dev/null 2>&1 || {
      log_error "missing required command: $c"
      missing=1
    }
  done
  [[ "$missing" == "0" ]] || return "$EX_CONFIG"
}
