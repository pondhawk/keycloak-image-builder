#!/usr/bin/env bash
# lib/systemd.sh — systemd/journald helpers for the Keycloak service (ADR-0005).
# shellcheck shell=bash

readonly KC_SERVICE="keycloak.service"
readonly KC_CONFIG_SERVICE="keycloak-config.service"

# sd_action <start|stop|restart> — mutating; dry-run aware.
sd_action() {
  local action="$1"
  is_dry_run || require_cmd systemctl || return "$EX_CONFIG"
  run systemctl "$action" "$KC_SERVICE"
}

# sd_status — non-mutating status of the service.
sd_status() {
  require_cmd systemctl || return "$EX_CONFIG"
  systemctl --no-pager status "$KC_SERVICE"
}

# sd_logs <journalctl-args...> — application logs for keycloak.service.
sd_logs() {
  require_cmd journalctl || return "$EX_CONFIG"
  journalctl -u "$KC_SERVICE" "$@"
}

# sd_journal <journalctl-args...> — journal for both units (boot + service).
sd_journal() {
  require_cmd journalctl || return "$EX_CONFIG"
  journalctl -u "$KC_SERVICE" -u "$KC_CONFIG_SERVICE" "$@"
}
