#!/usr/bin/env bash
# subcommand: upgrade — replace an EXISTING install with a new Keycloak version.
# The DB vendor is read from the model's keycloak.conf, never a flag, so an
# upgrade cannot change the image's baked vendor (its reason to exist).
# Safe swap: the current install is moved aside and kept until the new version
# installs and builds; only then is the previous version deleted. A failed
# upgrade rolls back to the previous install — you're never stranded. There is no
# persistent side-by-side and no `current` symlink; the old copy exists only for
# the duration of the upgrade. Reuses the install pipeline.
# shellcheck shell=bash

# shellcheck source=./install.sh
source "$KCIMAGE_CMD_DIR/install.sh"

_upgrade_usage() {
  cat << EOF
Usage: kcimage upgrade --keycloak-version <ver> [options]

Upgrade the Keycloak version on a model that already has an install. The DB
vendor is inherited from the existing install, so an upgrade never changes the
image's baked vendor. The current install is kept until the new version builds,
then removed; a failed upgrade rolls back. Use 'kcimage install' for a first
(greenfield) install instead.

Options:
  --keycloak-version <ver>   New Keycloak version, e.g. 26.2.0 (required)
  --java-package <pkg>       OpenJDK package (default: java-${KIB_JAVA_MAJOR}-openjdk-headless)
  --providers-dir <dir>      Custom provider JARs (default: ~/keycloak-custom-providers)
  -h, --help                 Show this help
EOF
}

cmd_upgrade() {
  local kc_version="" providers_dir=""
  local conf_dir="$KC_CONF"
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
  guard_not_live_node "upgrade" || return $?
  _install_check_privileges || return "$EX_CONFIG"

  local vendor
  vendor="$(_read_installed_vendor "$conf_dir")" || {
    log_error "no existing install found ($conf_dir/keycloak.conf missing)."
    log_error "Run 'kcimage install --keycloak-version <ver> --db-vendor <postgres|mysql>' first."
    return "$EX_CONFIG"
  }

  confirm "Upgrade to Keycloak $kc_version (db=$vendor). The current install is kept until the new one builds, then removed." || return $?

  log_info "upgrading to Keycloak $kc_version (db=$vendor)"
  local bak="${KC_OPT}.bak"
  run rm -rf "$bak"
  run mv "$KC_OPT" "$bak" || {
    log_error "could not move the current install aside; nothing changed"
    return "$EX_CONFIG"
  }
  if _install_core "$kc_version" "$vendor" "$java_pkg" "$conf_dir" "$providers_dir"; then
    run rm -rf "$bak"
    log_info "upgrade complete: previous version removed"
  else
    log_error "upgrade failed — rolling back to the previous install"
    run rm -rf "$KC_OPT"
    run mv "$bak" "$KC_OPT"
    return "$EX_CONFIG"
  fi
}
