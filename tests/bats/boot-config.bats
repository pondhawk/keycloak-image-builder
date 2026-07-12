#!/usr/bin/env bats
# boot/configure-node.sh — the user-data split, exercised via env overrides so no
# IMDS is touched. Validates the security-critical property: secrets go to the
# tmpfs file, never to keycloak.env.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$REPO_ROOT/boot/configure-node.sh"
  ETC="$BATS_TEST_TMPDIR/etc"
  RUN="$BATS_TEST_TMPDIR/run"
  USERDATA=$'KC_DB_URL=jdbc:mysql://db.internal:3306/keycloak\nKC_DB_USERNAME=kcapp\nKC_DB_PASSWORD=s3cr3t!\nKC_HOSTNAME=https://auth.example.com\nJAVA_OPTS_APPEND=-Xmx1g'
}

_run_boot() { # <user-data>
  run env KIB_ETC="$ETC" KIB_RUN="$RUN" NODE_PRIVATE_IP="10.0.1.42" \
    KIB_USERDATA="$1" bash "$SCRIPT"
}

@test "non-secret keys go to keycloak.env (incl. bind address from IMDS)" {
  _run_boot "$USERDATA"
  [ "$status" -eq 0 ]
  grep -q '^KC_DB_URL=jdbc:mysql://db.internal:3306/keycloak$' "$ETC/keycloak.env"
  grep -q '^KC_HOSTNAME=https://auth.example.com$' "$ETC/keycloak.env"
  grep -q '^JAVA_OPTS_APPEND=-Xmx1g$' "$ETC/keycloak.env"
  grep -q '^KC_CACHE_EMBEDDED_NETWORK_BIND_ADDRESS=10.0.1.42$' "$ETC/keycloak.env"
}

@test "secret keys go to secrets.env" {
  _run_boot "$USERDATA"
  [ "$status" -eq 0 ]
  grep -q '^KC_DB_USERNAME=kcapp$' "$RUN/secrets.env"
  grep -q '^KC_DB_PASSWORD=s3cr3t!$' "$RUN/secrets.env"
}

@test "the password never lands in keycloak.env" {
  _run_boot "$USERDATA"
  [ "$status" -eq 0 ]
  ! grep -q 's3cr3t' "$ETC/keycloak.env"
}

@test "secrets.env is mode 0640" {
  _run_boot "$USERDATA"
  [ "$status" -eq 0 ]
  [ "$(stat -c '%a' "$RUN/secrets.env")" = "640" ]
}

@test "bootstrap admin routes to secrets.env when present" {
  _run_boot "$USERDATA"$'\nKC_BOOTSTRAP_ADMIN_USERNAME=admin\nKC_BOOTSTRAP_ADMIN_PASSWORD=init'
  [ "$status" -eq 0 ]
  grep -q '^KC_BOOTSTRAP_ADMIN_USERNAME=admin$' "$RUN/secrets.env"
  ! grep -q 'BOOTSTRAP' "$ETC/keycloak.env"
}

@test "unrelated lines are ignored" {
  _run_boot "$USERDATA"$'\n# a comment\nSOMETHING_ELSE=nope'
  [ "$status" -eq 0 ]
  ! grep -q 'SOMETHING_ELSE' "$ETC/keycloak.env" "$RUN/secrets.env"
}

@test "fails when a required key is missing" {
  _run_boot $'KC_DB_URL=jdbc:mysql://d/k\nKC_HOSTNAME=https://h'
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing required keys"* ]]
  [[ "$output" == *"KC_DB_PASSWORD"* ]]
}
