#!/usr/bin/env bash
# subcommand: selinux — manage SELinux file contexts for KDT paths (ADR-0011).
# shellcheck shell=bash

_selinux_usage() {
  cat << EOF
Usage: kcadmin selinux apply [--fc <file>]

Register KDT file-context rules (semanage fcontext) and relabel (restorecon).

  apply           Add fcontexts and relabel KDT paths
  --fc <file>     fcontext rules file (default: auto-detected)
  -h, --help      Show this help
EOF
}

_selinux_cmd_apply() {
  local fc=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --fc)
        fc="${2:-}"
        shift 2
        ;;
      -h | --help)
        _selinux_usage
        return 0
        ;;
      *)
        log_error "selinux apply: unknown argument: $1"
        return "$EX_USAGE"
        ;;
    esac
  done
  if [[ -z "$fc" ]]; then
    fc="$(_resolve_selinux_fc)" || {
      log_error "selinux: cannot locate fcontext file"
      return "$EX_CONFIG"
    }
  fi
  selinux_apply "$fc"
}

cmd_selinux() {
  case "${1:-}" in
    apply)
      shift
      _selinux_cmd_apply "$@"
      ;;
    -h | --help)
      _selinux_usage
      return 0
      ;;
    "")
      log_error "selinux: missing action (try: apply)"
      _selinux_usage
      return "$EX_USAGE"
      ;;
    *)
      log_error "selinux: unknown action: $1"
      _selinux_usage
      return "$EX_USAGE"
      ;;
  esac
}
