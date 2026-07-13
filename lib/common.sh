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
readonly KIB_KEYCLOAK_BASELINE="26"
readonly KIB_JAVA_MAJOR="21"

# --- Filesystem layout (ADR-0001) ---
# Everything Keycloak-the-server lives under /opt/keycloak (KEYCLOAK_HOME), the
# native Keycloak layout: one version, no versioned subdir, no `current` symlink
# (this is an image-building node, never a production node — no side-by-side).
# Only ephemeral boot-injected config/secrets live outside, on tmpfs (/run).
# The KIB_* env vars are test hooks (like the boot script's KIB_ETC/KIB_RUN):
# they let Bats point a command at a temp dir instead of real system paths. They
# are NOT operator options and are not exposed as flags.
readonly KC_OPT="${KIB_HOME:-/opt/keycloak}"     # KEYCLOAK_HOME — Keycloak extracted here
readonly KC_CONF="${KIB_CONF_DIR:-$KC_OPT/conf}" # native config dir (keycloak.conf)
readonly KC_DATA="$KC_OPT/data"                  # keycloak-owned runtime data (gzip cache, tx logs)
readonly KC_RUN="${KIB_RUN:-/run/keycloak}"      # tmpfs — boot-injected env + secrets only
readonly KC_USER="keycloak"
readonly KC_GROUP="keycloak"
readonly KC_SYSTEMD_DIR="${KIB_SYSTEMD_DIR:-/usr/lib/systemd/system}"
readonly KC_BOOT_DIR="/usr/local/lib/keycloak"

# --- Keycloak distribution source ---
readonly KEYCLOAK_DOWNLOAD_BASE="https://github.com/keycloak/keycloak/releases/download"
# Keycloak GPG-signs every release asset with this key ("Keycloak Bot"). The
# fingerprint is the trust anchor for verifying the downloaded distribution
# before it is baked into the image (install.sh, ADR-0004). It is published
# officially at https://www.keycloak.org/keys (key "keycloak-2.asc"); the matching
# public key is committed at templates/keycloak-release-key.asc (sourced from that
# page) so verification needs no keyserver. NOTE: this key expires 2027-02-12 —
# refresh the committed key + fingerprint from keycloak.org/keys when it rotates.
readonly KEYCLOAK_SIGNING_KEY_FPR="861AB50E8CC6611FB6BC01A6B8F12EA26FD6EEBA"

# is_dry_run — true when --dry-run is active.
is_dry_run() { [[ "${DRY_RUN:-0}" == "1" ]]; }

# kib_user_home — home dir of the invoking user (works under sudo, where $HOME
# would be root's). Used to locate ~/keycloak-custom-providers.
kib_user_home() {
  local u="${SUDO_USER:-${USER:-root}}" h
  h="$(getent passwd "$u" 2> /dev/null | cut -d: -f6)" || true
  if [[ -n "$h" ]]; then printf '%s' "$h"; else printf '%s' "${HOME:-/root}"; fi
}

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

# confirm <prompt> — interactive safety gate for mutating commands. There is
# deliberately NO --yes/--force bypass: a flag baked into shell history would
# defeat the point, since an accidental up-arrow re-run replays the line verbatim
# (coding standards / ADR intent). Dry-run skips it (nothing happens). With no
# terminal to read from, it refuses rather than hang or silently proceed.
confirm() {
  local prompt="$1" reply
  if is_dry_run; then return 0; fi
  if [[ ! -t 0 ]]; then
    log_error "refusing to proceed without an interactive confirmation (no terminal); preview with --dry-run"
    return "$EX_CONFIG"
  fi
  printf '%s [y/N] ' "$prompt" >&2
  read -r reply || reply=""
  case "$reply" in
    y | Y | yes | YES | Yes) return 0 ;;
    *)
      log_warn "aborted"
      return "$EX_CONFIG"
      ;;
  esac
}

# _keycloak_is_active — true when keycloak.service is running. On the model
# instance Keycloak is built + sealed but never started (enabled-but-inactive);
# on a production ASG node it is active. Test hook:
# KIB_ASSUME_KEYCLOAK_ACTIVE=1 forces "active" without systemd.
_keycloak_is_active() {
  if [[ "${KIB_ASSUME_KEYCLOAK_ACTIVE:-0}" == "1" ]]; then return 0; fi
  systemctl is-active --quiet keycloak.service 2> /dev/null
}

# guard_not_live_node <action> — refuse a destructive/build op when Keycloak is
# running. If the service is up, this is almost certainly a live node (cattle),
# not the model instance, so refuse rather than break it. No bypass flag; the
# honest escape hatch is `systemctl stop keycloak`, never needed on a real model.
guard_not_live_node() {
  local action="${1:-proceed}"
  if is_dry_run; then return 0; fi
  if _keycloak_is_active; then
    log_error "keycloak.service is running — this looks like a live node, not a model instance."
    log_error "Refusing to $action. If this really is your model, stop it first: systemctl stop keycloak"
    return "$EX_CONFIG"
  fi
}
