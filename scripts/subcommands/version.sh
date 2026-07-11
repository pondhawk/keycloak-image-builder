#!/usr/bin/env bash
# subcommand: version — print KDT and baseline versions.
# shellcheck shell=bash

cmd_version() {
  # VERSION lives at repo root (dev) or $LIBDIR/VERSION (installed).
  local kdt_version="unknown" candidate
  for candidate in "$KCADMIN_BIN_DIR/../VERSION" "$KCADMIN_LIB_DIR/../VERSION"; do
    if [[ -f "$candidate" ]]; then
      kdt_version="$(< "$candidate")"
      break
    fi
  done
  printf 'kcadmin (KDT) %s\n' "$kdt_version"
  printf 'keycloak baseline: %s.x\n' "$KDT_KEYCLOAK_BASELINE"
  printf 'java: OpenJDK %s\n' "$KDT_JAVA_MAJOR"
}
