#!/usr/bin/env bats
# seal — dry-run planning + the neutrality gate (--check, safe to run).
# Config dir and tmpfs dir are pointed at temp dirs via the KIB_CONF_DIR/KIB_RUN
# test hooks (seal has no path flags).

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  KCIMAGE="$REPO_ROOT/scripts/kcimage"
  CONF="$BATS_TEST_TMPDIR/conf"
  RUN="$BATS_TEST_TMPDIR/run"
  mkdir -p "$CONF" "$RUN"
}

@test "seal --help exits 0" {
  run "$KCIMAGE" seal --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Sanitize this instance"* ]]
}

@test "dry-run seal plans sanitization and changes nothing" {
  run env KIB_CONF_DIR="$CONF" KIB_RUN="$RUN" "$KCIMAGE" --dry-run seal
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run]"* ]]
}

@test "gate passes on a neutral config dir (comment mentioning 'secrets' is ignored)" {
  # The real rendered keycloak.conf has a comment header that literally says
  # "secrets"/"endpoints"; the gate must scan directive lines only.
  cat > "$CONF/keycloak.conf" << 'CONF'
# keycloak.conf — NEUTRAL. Contains NO endpoints, hostnames, or secrets.
db=mysql
cache-stack=jdbc-ping
CONF
  run env KIB_CONF_DIR="$CONF" KIB_RUN="$RUN" "$KCIMAGE" seal --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"gate passed"* ]]
}

@test "gate fails when a boot-injected env file survives on tmpfs" {
  printf 'db=mysql\n' > "$CONF/keycloak.conf"
  touch "$RUN/keycloak.env"
  run env KIB_CONF_DIR="$CONF" KIB_RUN="$RUN" "$KCIMAGE" seal --check
  [ "$status" -ne 0 ]
  [[ "$output" == *"sensitive file still present"* ]]
}

@test "gate fails when a secret pattern is present" {
  printf 'db-password=hunter2\n' > "$CONF/keycloak.conf"
  run env KIB_CONF_DIR="$CONF" KIB_RUN="$RUN" "$KCIMAGE" seal --check
  [ "$status" -ne 0 ]
  [[ "$output" == *"possible secret/endpoint"* ]]
}

@test "seal refuses on a running (live) node" {
  export KIB_ASSUME_KEYCLOAK_ACTIVE=1
  run env KIB_CONF_DIR="$CONF" KIB_RUN="$RUN" "$KCIMAGE" seal
  [ "$status" -ne 0 ]
  [[ "$output" == *"live node"* ]]
}
