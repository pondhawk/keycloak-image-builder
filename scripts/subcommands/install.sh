#!/usr/bin/env bash
# subcommand: install — install/update Keycloak on the model instance and
# prepare it to be imaged (ADR-0001/0002/0003/0004/0011).
# Lays down Java, the distribution (side-by-side), the directory tree, the
# service user, the neutral keycloak.conf, runs kc.sh build, and applies SELinux
# file contexts. Idempotent and fail-safe; never overwrites a working install.
# shellcheck shell=bash

_install_usage() {
  cat << EOF
Usage: kcimage install --keycloak-version <ver> --db-vendor <postgres|mysql> [options]

Establish a fresh Keycloak install (lineage) on a clean model instance and
prepare it for imaging. To change the version of an EXISTING install, use
'kcimage upgrade' (which keeps the baked DB vendor). install is greenfield-only.

Options:
  --keycloak-version <ver>   Keycloak version, e.g. 26.1.4 (required)
  --db-vendor <v>            postgres | mysql (required; baked into the image)
  --java-package <pkg>       OpenJDK package (default: java-${KIB_JAVA_MAJOR}-openjdk-headless)
  --etc-dir <dir>            Config dir (default: /etc/keycloak)
  --providers-dir <dir>      Custom provider JARs (default: ~/keycloak-custom-providers)
  -h, --help                 Show this help
EOF
}

_install_validate_version() {
  local v="$1" major
  if [[ ! "$v" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
    log_error "invalid --keycloak-version: '$v' (expected e.g. 26.1.4)"
    return "$EX_USAGE"
  fi
  major="${v%%.*}"
  # Hard floor: the baked config is Keycloak 26-era (jdbc-ping cache stack,
  # KC_BOOTSTRAP_ADMIN_*, management port). Older majors would pass the model
  # gates but fail at node boot, so refuse them here.
  if ((major < KIB_KEYCLOAK_BASELINE)); then
    log_error "Keycloak $v is not supported: KIB requires ${KIB_KEYCLOAK_BASELINE}.x or newer."
    log_error "The baked config (jdbc-ping stack, KC_BOOTSTRAP_ADMIN_*) is ${KIB_KEYCLOAK_BASELINE}-era; older servers fail at boot."
    return "$EX_USAGE"
  fi
  if ((major > KIB_KEYCLOAK_BASELINE)); then
    log_warn "Keycloak major ${major} is newer than the ${KIB_KEYCLOAK_BASELINE}.x baseline (untested); proceeding"
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

_ensure_java() {
  local pkg="$1"
  if command -v java > /dev/null 2>&1 &&
    java -version 2>&1 | grep -qE "version \"${KIB_JAVA_MAJOR}([.\"]|$)"; then
    log_info "OpenJDK ${KIB_JAVA_MAJOR} already present"
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

_ensure_user() {
  if ! getent group "$KC_GROUP" > /dev/null 2>&1; then
    run groupadd --system "$KC_GROUP"
  fi
  if ! getent passwd "$KC_USER" > /dev/null 2>&1; then
    run useradd --system --gid "$KC_GROUP" --no-create-home \
      --home-dir "$KC_VAR_LIB" --shell /sbin/nologin "$KC_USER"
  fi
}

_ensure_dirs() {
  local etc_dir="$1"
  run install -d -o root -g root -m 0755 "$KC_OPT"
  run install -d -o root -g "$KC_GROUP" -m 0750 "$etc_dir"
  run install -d -o "$KC_USER" -g "$KC_GROUP" -m 0750 \
    "$KC_VAR_LIB" "$KC_VAR_LOG" "$KC_VAR_BACKUPS"
}

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

# _install_share_dir <name> — echo the resolved repo/tarball or installed dir.
_install_share_dir() {
  local name="$1" d
  for d in "$KCIMAGE_BIN_DIR/../$name" "$KCIMAGE_LIB_DIR/../$name"; do
    if [[ -d "$d" ]]; then
      readlink -f "$d"
      return 0
    fi
  done
  return 1
}

# Render the NEUTRAL keycloak.conf with the DB vendor; guard neutrality (ADR-0002).
_install_render_conf() {
  local vendor="$1" etc_dir="$2"
  local tpl_dir src rendered directives
  tpl_dir="$(_install_share_dir templates)" || {
    log_error "templates directory not found"
    return "$EX_CONFIG"
  }
  src="$tpl_dir/keycloak.conf"
  [[ -f "$src" ]] || {
    log_error "template not found: $src"
    return "$EX_CONFIG"
  }
  rendered="$(sed "s/__DB_VENDOR__/$vendor/g" "$src")"
  directives="$(grep -vE '^[[:space:]]*(#|$)' <<< "$rendered" || true)"
  if grep -qiE 'password|secret|://|amazonaws\.com' <<< "$directives"; then
    log_error "neutrality violation: keycloak.conf would contain a secret/endpoint"
    return "$EX_CONFIG"
  fi
  run install -d -m 0750 "$etc_dir"
  if is_dry_run; then
    log_info "[dry-run] would write $etc_dir/keycloak.conf (db=$vendor)"
    return 0
  fi
  printf '%s\n' "$rendered" > "$etc_dir/keycloak.conf"
  # The keycloak service user reads this at runtime via KC_CONFIG_FILE (the
  # process opens it directly, unlike keycloak.env which systemd reads as root),
  # so it must be group-owned by keycloak and group-readable.
  chown "root:$KC_GROUP" "$etc_dir/keycloak.conf"
  chmod 0640 "$etc_dir/keycloak.conf"
  log_info "rendered $etc_dir/keycloak.conf (db=$vendor, root:$KC_GROUP 0640)"
}

# Deploy custom provider JARs from the operator's providers dir into the active
# install before the build so they are baked in (ADR-0001). No-op if none. The
# source lives in the operator's home (~/keycloak-custom-providers by default),
# so JARs are re-deployed on every install/update and carry across upgrades.
# Themes ship as provider JARs too (best practice), so only JARs are handled.
_install_deploy_custom() {
  local src="$1" dst="$KC_CURRENT/providers" entries
  entries=("$src"/*.jar)
  [[ -e "${entries[0]}" ]] || return 0
  log_info "deploying custom providers from $src"
  run install -d "$dst"
  run cp -a "$src"/*.jar "$dst/"
}

# Run kc.sh build against the active install, using the neutral keycloak.conf.
_install_build() {
  local etc_dir="$1"
  local kcsh="$KC_CURRENT/bin/kc.sh"
  if ! is_dry_run && [[ ! -x "$kcsh" ]]; then
    log_error "cannot build: $kcsh not found"
    return "$EX_CONFIG"
  fi
  log_info "building Keycloak (optimized)"
  run env KC_CONFIG_FILE="$etc_dir/keycloak.conf" "$kcsh" build
}

# Apply SELinux file contexts for KIB paths (ADR-0011); skip if SELinux is off.
_install_selinux() {
  if ! selinux_available; then
    log_warn "SELinux not enabled; skipping context setup (Enforcing required in production — ADR-0011)"
    return 0
  fi
  local fc
  if ! fc="$(_resolve_selinux_fc)"; then
    log_warn "SELinux fcontext file not found; skipping context setup"
    return 0
  fi
  selinux_apply "$fc"
}

# Place the systemd units + boot artifacts and enable the service (ADR-0005).
# Baked into the AMI so an ASG node boots Keycloak automatically. This is why
# there is no separate "install the toolkit" step — `install` bakes the runtime.
_install_systemd() {
  local sd_src boot_src
  sd_src="$(_install_share_dir systemd)" || {
    log_error "systemd/ directory not found"
    return "$EX_CONFIG"
  }
  boot_src="$(_install_share_dir boot)" || {
    log_error "boot/ directory not found"
    return "$EX_CONFIG"
  }

  # Boot script (self-contained; the unit's ExecStart path).
  run install -d -m 0755 "$KC_BOOT_DIR"
  run install -m 0755 "$boot_src/configure-node.sh" "$KC_BOOT_DIR/configure-node.sh"

  # systemd units
  run install -d -m 0755 "$KC_SYSTEMD_DIR"
  run install -m 0644 "$sd_src/keycloak.service" "$sd_src/keycloak-config.service" \
    "$KC_SYSTEMD_DIR/"

  if is_dry_run; then
    log_info "[dry-run] would daemon-reload and enable keycloak-config.service + keycloak.service"
    return 0
  fi
  systemctl daemon-reload || log_warn "systemctl daemon-reload failed"
  systemctl enable keycloak-config.service keycloak.service > /dev/null 2>&1 ||
    log_warn "could not enable units (enable them before imaging)"
  log_info "installed systemd units + boot script"
}

# Switch the 'current' symlink to this version. install and upgrade always do
# this once the distribution is in place.
_activate_current() {
  local ver="$1"
  run ln -sfn "keycloak-$ver" "$KC_CURRENT"
  log_info "current -> keycloak-$ver"
}

# Read the DB vendor baked into the model's keycloak.conf. Prints it, or fails
# with non-zero if there is no rendered config (i.e. no established install).
_read_installed_vendor() {
  local etc_dir="$1" line
  local conf="$etc_dir/keycloak.conf"
  [[ -f "$conf" ]] || return 1
  while IFS= read -r line; do
    case "$line" in
      db=*)
        printf '%s' "${line#db=}"
        return 0
        ;;
    esac
  done < "$conf"
  return 1
}

# install is greenfield-only: refuse if the model already has an install. The
# correct way to change an existing install's version is 'upgrade'; to start a
# different lineage (e.g. another DB vendor) is 'clean' then 'install'.
_install_guard_greenfield() {
  local etc_dir="$1" vendor ver
  [[ -e "$KC_CURRENT" || -f "$etc_dir/keycloak.conf" ]] || return 0
  vendor="$(_read_installed_vendor "$etc_dir" 2> /dev/null || true)"
  ver="$(readlink "$KC_CURRENT" 2> /dev/null || true)"
  ver="${ver#keycloak-}"
  log_error "already installed (db=${vendor:-?}, keycloak=${ver:-?})."
  log_error "Use 'kcimage upgrade' to change the Keycloak version, or 'kcimage clean' to start over."
  return "$EX_CONFIG"
}

# Shared install/upgrade pipeline. Version + vendor are already resolved by the
# caller (install takes vendor from --db-vendor; upgrade reads it from the model).
_install_core() {
  local kc_version="$1" vendor="$2" java_pkg="$3" etc_dir="$4" providers_dir="$5"
  _ensure_java "$java_pkg" || return $?
  _ensure_user || return $?
  _ensure_dirs "$etc_dir" || return $?
  _install_keycloak_dist "$kc_version" || return $?
  _activate_current "$kc_version" || return $?
  _install_render_conf "$vendor" "$etc_dir" || return $?
  _install_deploy_custom "${providers_dir:-$(kib_user_home)/keycloak-custom-providers}" || return $?
  _install_build "$etc_dir" || return $?
  _install_systemd || return $?
  _install_selinux || return $?
  log_info "install complete: $KC_OPT/keycloak-$kc_version (current; ready to verify + seal)"
}

cmd_install() {
  local kc_version="" vendor="" etc_dir="$KC_ETC" providers_dir=""
  local java_pkg="java-${KIB_JAVA_MAJOR}-openjdk-headless"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --keycloak-version)
        kc_version="${2:-}"
        shift 2
        ;;
      --db-vendor)
        vendor="${2:-}"
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
  case "$vendor" in
    postgres | mysql) ;;
    "")
      log_error "install: --db-vendor is required (postgres|mysql)"
      return "$EX_USAGE"
      ;;
    *)
      log_error "install: invalid --db-vendor: '$vendor' (postgres|mysql)"
      return "$EX_USAGE"
      ;;
  esac
  _install_validate_version "$kc_version" || return "$EX_USAGE"
  guard_not_live_node "install" || return $?
  _install_check_privileges || return "$EX_CONFIG"
  _install_guard_greenfield "$etc_dir" || return $?
  confirm "Install Keycloak $kc_version (db=$vendor) on this model instance." || return $?

  log_info "installing Keycloak $kc_version (db=$vendor, java=$java_pkg)"
  _install_core "$kc_version" "$vendor" "$java_pkg" "$etc_dir" "$providers_dir"
}
