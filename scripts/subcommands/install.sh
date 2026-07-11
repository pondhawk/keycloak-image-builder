#!/usr/bin/env bash
# subcommand: install — lay down Java, the Keycloak distribution, the directory
# tree, and the service user (blueprint §19 M3; ADR-0001/0004).
# Idempotent and fail-safe: never overwrites an existing working install.
# shellcheck shell=bash

_install_usage() {
  cat << EOF
Usage: kcadmin install --keycloak-version <ver> [options]

Lay down OpenJDK, the Keycloak distribution (side-by-side), the directory tree,
and the 'keycloak' service user. Safe to re-run.

Options:
  --keycloak-version <ver>   Keycloak version to install, e.g. 26.1.4 (required)
  --java-package <pkg>       OpenJDK package (default: java-${KDT_JAVA_MAJOR}-openjdk-headless)
  --activate                 Point /opt/keycloak/current at this version
  -h, --help                 Show this help
EOF
}

# Validate a Keycloak version string (e.g. 26 or 26.1 or 26.1.4).
_install_validate_version() {
  local v="$1"
  if [[ ! "$v" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
    log_error "invalid --keycloak-version: '$v' (expected e.g. 26.1.4)"
    return "$EX_USAGE"
  fi
  if [[ "${v%%.*}" != "$KDT_KEYCLOAK_BASELINE" ]]; then
    log_warn "requested Keycloak major ${v%%.*} differs from baseline ${KDT_KEYCLOAK_BASELINE}.x"
  fi
}

# Real runs need root (users, /opt, /etc). Dry-run is exempt.
_install_check_privileges() {
  if is_dry_run; then
    [[ "${EUID:-$(id -u)}" -eq 0 ]] || log_warn "dry-run: not root; real run would require root"
    return 0
  fi
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    log_error "install must run as root"
    return "$EX_CONFIG"
  fi
}

# Ensure an OpenJDK matching the baseline major is available.
_ensure_java() {
  local pkg="$1"
  if command -v java > /dev/null 2>&1 &&
    java -version 2>&1 | grep -qE "version \"${KDT_JAVA_MAJOR}([.\"]|$)"; then
    log_info "OpenJDK ${KDT_JAVA_MAJOR} already present"
    return 0
  fi
  if is_dry_run; then
    log_info "[dry-run] would install $pkg"
    return 0
  fi
  log_info "installing $pkg"
  run dnf install -y "$pkg" || {
    log_error "failed to install $pkg"
    return "$EX_CONFIG"
  }
}

# Ensure the 'keycloak' system group and user exist (no login).
_ensure_user() {
  if ! getent group "$KC_GROUP" > /dev/null 2>&1; then
    run groupadd --system "$KC_GROUP"
  fi
  if ! getent passwd "$KC_USER" > /dev/null 2>&1; then
    run useradd --system --gid "$KC_GROUP" --no-create-home \
      --home-dir "$KC_VAR_LIB" --shell /sbin/nologin "$KC_USER"
  fi
}

# Ensure the directory tree with ownership/permissions (ADR-0001).
_ensure_dirs() {
  run install -d -o root -g root -m 0755 "$KC_OPT"
  run install -d -o root -g root -m 0755 \
    "$KC_CUSTOM" "$KC_CUSTOM/themes" "$KC_CUSTOM/providers" "$KC_CUSTOM/scripts"
  run install -d -o root -g "$KC_GROUP" -m 0750 "$KC_ETC"
  run install -d -o "$KC_USER" -g "$KC_GROUP" -m 0750 \
    "$KC_VAR_LIB" "$KC_VAR_LOG" "$KC_VAR_BACKUPS"
}

# Download and place the Keycloak distribution side-by-side. Never overwrite.
_install_keycloak_dist() {
  local ver="$1"
  local target="$KC_OPT/keycloak-$ver"
  if [[ -x "$target/bin/kc.sh" ]]; then
    log_info "Keycloak $ver already installed (skipping): $target"
    return 0
  fi

  local url="$KEYCLOAK_DOWNLOAD_BASE/$ver/keycloak-$ver.tar.gz"
  if is_dry_run; then
    log_info "[dry-run] would download $url and extract to $target"
    return 0
  fi

  require_cmd curl tar || return "$EX_CONFIG"
  local tmp
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN

  log_info "downloading $url"
  run curl -fSL -o "$tmp/kc.tgz" "$url" || {
    log_error "download failed: $url"
    return "$EX_CONFIG"
  }
  run tar -xzf "$tmp/kc.tgz" -C "$tmp" || {
    log_error "extract failed"
    return "$EX_CONFIG"
  }
  if [[ ! -x "$tmp/keycloak-$ver/bin/kc.sh" ]]; then
    log_error "unexpected archive layout: bin/kc.sh not found for $ver"
    return "$EX_CONFIG"
  fi
  run mv "$tmp/keycloak-$ver" "$target" || return "$EX_CONFIG"
  run chown -R root:root "$target"
  log_info "installed: $target"
}

# Point 'current' at this version on first install or when --activate is given.
# Otherwise leave it (upgrade flow owns the swap — ADR-0006).
_maybe_set_current() {
  local ver="$1" activate="$2"
  if [[ "$activate" == "1" || ! -e "$KC_CURRENT" ]]; then
    run ln -sfn "keycloak-$ver" "$KC_CURRENT"
    log_info "current -> keycloak-$ver"
  else
    log_info "current unchanged ($(readlink "$KC_CURRENT" 2> /dev/null || echo '?')); use 'upgrade' to activate"
  fi
}

cmd_install() {
  local kc_version="" java_pkg="java-${KDT_JAVA_MAJOR}-openjdk-headless" activate=0
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
      --activate)
        activate=1
        shift
        ;;
      -h | --help)
        _install_usage
        return 0
        ;;
      *)
        log_error "install: unknown argument: $1"
        _install_usage
        return "$EX_USAGE"
        ;;
    esac
  done

  [[ -n "$kc_version" ]] || {
    log_error "install: --keycloak-version is required (e.g. 26.1.4)"
    return "$EX_USAGE"
  }
  _install_validate_version "$kc_version" || return "$EX_USAGE"
  _install_check_privileges || return "$EX_CONFIG"

  log_info "installing Keycloak $kc_version (java package: $java_pkg)"
  _ensure_java "$java_pkg" || return $?
  _ensure_user || return $?
  _ensure_dirs || return $?
  _install_keycloak_dist "$kc_version" || return $?
  _maybe_set_current "$kc_version" "$activate" || return $?
  log_info "install complete: $KC_OPT/keycloak-$kc_version"
}
