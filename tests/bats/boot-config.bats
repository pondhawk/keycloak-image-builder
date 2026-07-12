#!/usr/bin/env bats
# boot/configure-node.sh — the secret split, exercised via env overrides so no
# IMDS/AWS is touched. Validates the security-critical property: secrets go to
# the tmpfs file, never to keycloak.env.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$REPO_ROOT/boot/configure-node.sh"
  ETC="$BATS_TEST_TMPDIR/etc"
  RUN="$BATS_TEST_TMPDIR/run"
  SECRET='{"db_url":"jdbc:mysql://db.internal:3306/keycloak","db_username":"kcapp","db_password":"s3cr3t!","hostname":"https://auth.example.com","java_opts_append":"-Xmx1g"}'
}

_run_boot() { # <secret-json>
  run env KDT_ETC="$ETC" KDT_RUN="$RUN" NODE_PRIVATE_IP="10.0.1.42" \
    KDT_SECRET_JSON="$1" bash "$SCRIPT"
}

@test "splits non-secret fields into keycloak.env" {
  _run_boot "$SECRET"
  [ "$status" -eq 0 ]
  grep -q '^KC_DB_URL=jdbc:mysql://db.internal:3306/keycloak$' "$ETC/keycloak.env"
  grep -q '^KC_HOSTNAME=https://auth.example.com$' "$ETC/keycloak.env"
  grep -q '^KC_CACHE_EMBEDDED_NETWORK_BIND_ADDRESS=10.0.1.42$' "$ETC/keycloak.env"
}

@test "writes secret fields to secrets.env" {
  _run_boot "$SECRET"
  [ "$status" -eq 0 ]
  grep -q '^KC_DB_USERNAME=kcapp$' "$RUN/secrets.env"
  grep -q '^KC_DB_PASSWORD=s3cr3t!$' "$RUN/secrets.env"
}

@test "keeps the password OUT of keycloak.env" {
  _run_boot "$SECRET"
  [ "$status" -eq 0 ]
  ! grep -q 's3cr3t' "$ETC/keycloak.env"
}

@test "secrets.env is mode 0640" {
  _run_boot "$SECRET"
  [ "$status" -eq 0 ]
  [ "$(stat -c '%a' "$RUN/secrets.env")" = "640" ]
}

@test "includes bootstrap admin when present in the secret" {
  _run_boot '{"db_url":"jdbc:mysql://d/k","db_username":"u","db_password":"p","hostname":"https://h","bootstrap_admin_username":"admin","bootstrap_admin_password":"init"}'
  [ "$status" -eq 0 ]
  grep -q '^KC_BOOTSTRAP_ADMIN_USERNAME=admin$' "$RUN/secrets.env"
}

@test "omits bootstrap admin when absent" {
  _run_boot "$SECRET"
  [ "$status" -eq 0 ]
  ! grep -q 'BOOTSTRAP' "$RUN/secrets.env"
}

@test "fails when a required field is missing" {
  _run_boot '{"db_url":"jdbc:mysql://d/k","hostname":"https://h"}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing required field"* ]]
}
