#!/usr/bin/env bash
# subcommand: version — print KIB and baseline versions.
# shellcheck shell=bash

cmd_version() {
  # VERSION lives at repo root (dev) or $LIBDIR/VERSION (installed).
  local kdt_version="unknown" candidate
  for candidate in "$KCIMAGE_BIN_DIR/../VERSION" "$KCIMAGE_LIB_DIR/../VERSION"; do
    if [[ -f "$candidate" ]]; then
      kdt_version="$(< "$candidate")"
      break
    fi
  done
  printf 'kcimage (KIB) %s\n' "$kdt_version"
  printf 'keycloak baseline: %s.x\n' "$KIB_KEYCLOAK_BASELINE"
  printf 'java: OpenJDK %s\n' "$KIB_JAVA_MAJOR"
}
