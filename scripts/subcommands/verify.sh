#!/usr/bin/env bash
# subcommand: verify — golden-image / node validation (ADR-0012 pre-clean gate).
# Confirms KDT did its job (install/config/SELinux/units); it does NOT test
# Keycloak's own behaviour. Runtime health lives in `kcadmin health`.
# shellcheck shell=bash

_verify_usage() {
  cat << EOF
Usage: kcadmin verify [--etc-dir <dir>] [--systemd-dir <dir>] [--home <dir>]

Validate that KDT provisioned this node correctly: Java, install, rendered
config, SELinux Enforcing, and systemd units.

  --etc-dir <dir>      Config dir (default: /etc/keycloak)
  --systemd-dir <dir>  Unit dir (default: /usr/lib/systemd/system)
  --home <dir>         Keycloak home (default: /opt/keycloak/current)
  -h, --help           Show this help
EOF
}

_verify_java() {
  if command -v java > /dev/null 2>&1 &&
    java -version 2>&1 | grep -qE "version \"${KDT_JAVA_MAJOR}([.\"]|$)"; then
    validate_item PASS Java "OpenJDK ${KDT_JAVA_MAJOR}"
  else
    validate_item FAIL Java "OpenJDK ${KDT_JAVA_MAJOR} not found"
  fi
}

_verify_install() {
  local home="$1"
  if [[ -x "$home/bin/kc.sh" ]]; then
    validate_item PASS install "$home"
  else
    validate_item FAIL install "kc.sh not found under $home"
  fi
  if [[ -e "$home/lib/quarkus" ]]; then
    validate_item PASS build "augmented server present"
  else
    validate_item FAIL build "server not built (run: kcadmin build)"
  fi
}

_verify_config() {
  local etc_dir="$1"
  if [[ -f "$etc_dir/keycloak.conf" ]] && grep -qE '^db=' "$etc_dir/keycloak.conf"; then
    validate_item PASS config "$etc_dir/keycloak.conf rendered"
  else
    validate_item FAIL config "keycloak.conf missing or has no db= (run: kcadmin configure)"
  fi
}

_verify_selinux() {
  local mode="Unknown"
  command -v getenforce > /dev/null 2>&1 && mode="$(getenforce 2> /dev/null || echo Unknown)"
  if [[ "$mode" == "Enforcing" ]]; then
    validate_item PASS SELinux "Enforcing"
  else
    validate_item FAIL SELinux "must be Enforcing (found: $mode) — ADR-0011"
  fi
}

_verify_units() {
  local sd_dir="$1" u missing=()
  for u in keycloak.service keycloak-config.service; do
    [[ -f "$sd_dir/$u" ]] || missing+=("$u")
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    validate_item PASS units "keycloak.service + keycloak-config.service"
  else
    validate_item FAIL units "missing: $(join_sp "${missing[@]}")"
  fi
}

cmd_verify() {
  local etc_dir="$KC_ETC" sd_dir="/usr/lib/systemd/system" home="$KC_CURRENT"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --etc-dir)
        etc_dir="${2:-}"
        shift 2
        ;;
      --systemd-dir)
        sd_dir="${2:-}"
        shift 2
        ;;
      --home)
        home="${2:-}"
        shift 2
        ;;
      -h | --help)
        _verify_usage
        return 0
        ;;
      *)
        log_error "verify: unknown argument: $1"
        _verify_usage
        return "$EX_USAGE"
        ;;
    esac
  done

  validate_reset
  _verify_java
  _verify_install "$home"
  _verify_config "$etc_dir"
  _verify_selinux
  _verify_units "$sd_dir"
  validate_summary
}
