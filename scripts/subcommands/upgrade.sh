#!/usr/bin/env bash
# subcommand: upgrade — move an EXISTING install to a new Keycloak version and
# prepare it to be re-imaged (ADR-0006 Phase 1: golden-instance version prep).
# The DB vendor is read from the model's keycloak.conf, never a flag, so an
# upgrade cannot change the image's baked vendor. Reuses the install pipeline.
# shellcheck shell=bash

# Reuse the shared install pipeline + helpers (_install_core, _read_installed_vendor,
# _install_validate_version, _install_check_privileges, ...).
# shellcheck source=./install.sh
source "$KCIMAGE_CMD_DIR/install.sh"

_upgrade_usage() {
  cat << EOF
Usage: kcimage upgrade --keycloak-version <ver> [options]

Upgrade the Keycloak version on a model that already has an install. The DB
vendor is inherited from the existing install, so an upgrade never changes the
image's baked vendor. The new version installs side-by-side and is activated.
Use 'kcimage install' for a first (greenfield) install instead.

Options:
  --keycloak-version <ver>   New Keycloak version, e.g. 26.2.0 (required)
  --java-package <pkg>       OpenJDK package (default: java-${KIB_JAVA_MAJOR}-openjdk-headless)
  --etc-dir <dir>            Config dir (default: /etc/keycloak)
  --providers-dir <dir>      Custom provider JARs (default: ~/keycloak-custom-providers)
  -h, --help                 Show this help
EOF
}

cmd_upgrade() {
  local kc_version="" etc_dir="$KC_ETC" providers_dir=""
  local java_pkg="java-${KIB_JAVA_MAJOR}-openjdk-headless"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --keycloak-version)
        kc_version="${2:-}"
        shift 2
        ;;
      --java-package)
        java_pkg="${2:-}"
        shift 2
        ;;
      --etc-dir)
        etc_dir="${2:-}"
        shift 2
        ;;
      --providers-dir)
        providers_dir="${2:-}"
        shift 2
        ;;
      -h | --help)
        _upgrade_usage
        return 0
        ;;
      *)
        log_error "upgrade: unknown argument: $1"
        _upgrade_usage
        return "$EX_USAGE"
        ;;
    esac
  done

  [[ -n "$kc_version" ]] || {
    log_error "upgrade: --keycloak-version is required (e.g. 26.2.0)"
    return "$EX_USAGE"
  }
  _install_validate_version "$kc_version" || return "$EX_USAGE"
  _install_check_privileges || return "$EX_CONFIG"

  local vendor
  vendor="$(_read_installed_vendor "$etc_dir")" || {
    log_error "no existing install found ($etc_dir/keycloak.conf missing)."
    log_error "Run 'kcimage install --keycloak-version <ver> --db-vendor <postgres|mysql>' first."
    return "$EX_CONFIG"
  }

  confirm "Upgrade to Keycloak $kc_version (db=$vendor) and switch the active version." || return $?

  log_info "upgrading to Keycloak $kc_version (db=$vendor, read from the existing install)"
  _install_core "$kc_version" "$vendor" "$java_pkg" "$etc_dir" "$providers_dir"
}
