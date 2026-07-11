#!/usr/bin/env bash
# subcommand: build — run `kc.sh build` for the active install (ADR-0004).
# Bakes the build-time options from keycloak.conf into an optimized server.
# shellcheck shell=bash

_build_usage() {
  cat << EOF
Usage: kcadmin build [--home <dir>]

Build (augment) the active Keycloak install from /etc/keycloak/keycloak.conf.

  --home <dir>   Keycloak home (default: $KC_CURRENT)
  -h, --help     Show this help
EOF
}

cmd_build() {
  local kc_home="$KC_CURRENT"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --home)
        kc_home="${2:-}"
        shift 2
        ;;
      -h | --help)
        _build_usage
        return 0
        ;;
      *)
        log_error "build: unknown argument: $1"
        _build_usage
        return "$EX_USAGE"
        ;;
    esac
  done

  local kcsh="$kc_home/bin/kc.sh"
  if ! is_dry_run; then
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
      log_error "build must run as root"
      return "$EX_CONFIG"
    fi
    if [[ ! -x "$kcsh" ]]; then
      log_error "Keycloak not installed at $kc_home (run: kcadmin install)"
      return "$EX_CONFIG"
    fi
  fi

  log_info "building Keycloak (optimized) at $kc_home"
  run env KC_CONFIG_FILE="$KC_ETC/keycloak.conf" "$kcsh" build
}
