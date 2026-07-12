#!/usr/bin/env bash
# subcommand: verify — golden-image / node validation (ADR-0012 pre-clean gate).
# Confirms KIB did its job (install/config/SELinux/units); it does NOT test
# Keycloak's own behaviour. Runtime health lives in `kcimage health`.
# shellcheck shell=bash

_verify_usage() {
  cat << EOF
Usage: kcimage verify [--etc-dir <dir>] [--systemd-dir <dir>] [--home <dir>]

Validate that KIB provisioned this node correctly: Java, install, rendered
config, SELinux Enforcing, and systemd units.

  --etc-dir <dir>      Config dir (default: /etc/keycloak)
  --systemd-dir <dir>  Unit dir (default: /usr/lib/systemd/system)
  --home <dir>         Keycloak home (default: /opt/keycloak/current)
  --providers-dir <d>  Custom provider JARs (default: ~/keycloak-custom-providers)
  -h, --help           Show this help
EOF
}

# Confirm every custom provider JAR was deployed into the install (ADR-0001).
_verify_custom_providers() {
  local providers_dir="$1" home="$2"
  local src="$providers_dir" dst="$home/providers"
  local entries missing=() f base
  entries=("$src"/*.jar)
  if [[ ! -e "${entries[0]}" ]]; then
    validate_item SKIP providers "no custom providers"
    return 0
  fi
  for f in "${entries[@]}"; do
    base="${f##*/}"
    [[ -f "$dst/$base" ]] || missing+=("$base")
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    validate_item PASS providers "all custom providers deployed to $dst"
  else
    validate_item FAIL providers "not deployed: $(join_sp "${missing[@]}")"
  fi
}

_verify_java() {
  if command -v java > /dev/null 2>&1 &&
    java -version 2>&1 | grep -qE "version \"${KIB_JAVA_MAJOR}([.\"]|$)"; then
    validate_item PASS Java "OpenJDK ${KIB_JAVA_MAJOR}"
  else
    validate_item FAIL Java "OpenJDK ${KIB_JAVA_MAJOR} not found"
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
    validate_item FAIL build "server not built (run: kcimage build)"
  fi
}

_verify_config() {
  local etc_dir="$1"
  if [[ -f "$etc_dir/keycloak.conf" ]] && grep -qE '^db=' "$etc_dir/keycloak.conf"; then
    validate_item PASS config "$etc_dir/keycloak.conf rendered"
  else
    validate_item FAIL config "keycloak.conf missing or has no db= (run: kcimage configure)"
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
  local etc_dir="$KC_ETC" sd_dir="$KC_SYSTEMD_DIR" home="$KC_CURRENT" providers_dir=""
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
      --providers-dir)
        providers_dir="${2:-}"
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
  _verify_custom_providers "${providers_dir:-$(kib_user_home)/keycloak-custom-providers}" "$home"
  validate_summary
}
