#!/usr/bin/env bash
# subcommand: configure — render config from templates into /etc/keycloak
# (blueprint §19 M4; ADR-0002).
#   keycloak.conf : NEUTRAL, build-time — vendor substituted at bake time.
#   keycloak.env  : environment-specific, runtime — rendered from the environment.
# shellcheck shell=bash

_configure_usage() {
  cat << EOF
Usage: kcadmin configure [--db-vendor <postgres|mysql>] [--env] [options]

Render config from templates (ADR-0002):
  --db-vendor <v>     Render keycloak.conf (neutral) with vendor postgres|mysql
  --env               Render keycloak.env from the current environment (envsubst)
  --etc-dir <dir>     Target config dir (default: /etc/keycloak)
  --templates-dir <d> Template source dir (default: auto-detected)
  -h, --help          Show this help

At least one of --db-vendor or --env is required.
EOF
}

# Echo the templates directory (repo layout or installed layout).
_configure_resolve_templates() {
  local d
  for d in "$KCADMIN_BIN_DIR/../templates" "$KCADMIN_LIB_DIR/../templates"; do
    if [[ -d "$d" ]]; then
      readlink -f "$d"
      return 0
    fi
  done
  return 1
}

# _write_file <path> <content> <mode> — dry-run aware.
_write_file() {
  local path="$1" content="$2" mode="${3:-0644}"
  if is_dry_run; then
    log_info "[dry-run] would write $path (mode $mode)"
    return 0
  fi
  printf '%s\n' "$content" > "$path"
  chmod "$mode" "$path"
}

# Render keycloak.conf (neutral) with the DB vendor; guard neutrality (ADR-0002).
_configure_render_conf() {
  local vendor="$1" tpl_dir="$2" etc_dir="$3"
  case "$vendor" in
    postgres | mysql) ;;
    *)
      log_error "invalid --db-vendor: '$vendor' (expected postgres|mysql)"
      return "$EX_USAGE"
      ;;
  esac
  local src="$tpl_dir/keycloak.conf"
  [[ -f "$src" ]] || {
    log_error "template not found: $src"
    return "$EX_CONFIG"
  }

  local rendered
  rendered="$(sed "s/__DB_VENDOR__/$vendor/g" "$src")"

  # Neutrality guard (ADR-0002): no secrets/endpoints in *directive* lines.
  # Comments are ignored so documentation wording cannot trip it.
  local directives
  directives="$(grep -vE '^[[:space:]]*(#|$)' <<< "$rendered" || true)"
  if grep -qiE 'password|secret|://|amazonaws\.com' <<< "$directives"; then
    log_error "neutrality violation: keycloak.conf would contain a secret/endpoint"
    return "$EX_CONFIG"
  fi

  run install -d -m 0750 "$etc_dir"
  _write_file "$etc_dir/keycloak.conf" "$rendered" 0640
  log_info "rendered $etc_dir/keycloak.conf (db=$vendor)"
}

# Render keycloak.env (environment-specific) from the current environment.
_configure_render_env() {
  local tpl_dir="$1" etc_dir="$2"
  local src="$tpl_dir/keycloak.env"
  [[ -f "$src" ]] || {
    log_error "template not found: $src"
    return "$EX_CONFIG"
  }
  require_cmd envsubst || return "$EX_CONFIG"

  local missing=() v
  for v in KC_DB_URL KC_HOSTNAME; do
    [[ -n "${!v:-}" ]] || missing+=("$v")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    log_error "cannot render keycloak.env; missing required env: $(join_sp "${missing[@]}")"
    return "$EX_CONFIG"
  fi

  # Only substitute the intended variables (leave any others untouched).
  local rendered
  # shellcheck disable=SC2016  # ${VARS} are envsubst's argument, not shell expansion
  rendered="$(envsubst '${KC_DB_URL} ${KC_HOSTNAME} ${NODE_PRIVATE_IP} ${JAVA_OPTS_APPEND}' < "$src")"

  run install -d -m 0750 "$etc_dir"
  _write_file "$etc_dir/keycloak.env" "$rendered" 0640
  log_info "rendered $etc_dir/keycloak.env"
}

cmd_configure() {
  local vendor="" etc_dir="$KC_ETC" tpl_override="" do_conf=0 do_env=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --db-vendor)
        vendor="${2:-}"
        do_conf=1
        shift 2
        ;;
      --env)
        do_env=1
        shift
        ;;
      --etc-dir)
        etc_dir="${2:-}"
        shift 2
        ;;
      --templates-dir)
        tpl_override="${2:-}"
        shift 2
        ;;
      -h | --help)
        _configure_usage
        return 0
        ;;
      *)
        log_error "configure: unknown argument: $1"
        _configure_usage
        return "$EX_USAGE"
        ;;
    esac
  done

  if [[ "$do_conf" -eq 0 && "$do_env" -eq 0 ]]; then
    log_error "configure: nothing to do (pass --db-vendor and/or --env)"
    return "$EX_USAGE"
  fi

  local tpl_dir
  if [[ -n "$tpl_override" ]]; then
    tpl_dir="$tpl_override"
  elif ! tpl_dir="$(_configure_resolve_templates)"; then
    log_error "configure: cannot locate templates directory"
    return "$EX_CONFIG"
  fi

  if [[ "$do_conf" -eq 1 ]]; then
    _configure_render_conf "$vendor" "$tpl_dir" "$etc_dir" || return $?
  fi
  if [[ "$do_env" -eq 1 ]]; then
    _configure_render_env "$tpl_dir" "$etc_dir" || return $?
  fi
}
