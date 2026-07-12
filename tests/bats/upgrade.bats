#!/usr/bin/env bats
# upgrade — dry-run / validation only. The DB vendor is read from the model's
# keycloak.conf, never a flag, so an upgrade cannot change the baked vendor.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  KCIMAGE="$REPO_ROOT/scripts/kcimage"
}

# A model with an existing install is simulated by a rendered keycloak.conf.
_seed_install() { # <etc-dir> <vendor>
  mkdir -p "$1"
  printf 'db=%s\n' "$2" > "$1/keycloak.conf"
}

@test "upgrade --help exits 0" {
  run "$KCIMAGE" upgrade --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Upgrade the Keycloak version"* ]]
}

@test "upgrade requires --keycloak-version" {
  local etc="$BATS_TEST_TMPDIR/etc"
  _seed_install "$etc" mysql
  run "$KCIMAGE" upgrade --etc-dir "$etc"
  [ "$status" -ne 0 ]
  [[ "$output" == *"--keycloak-version is required"* ]]
}

@test "upgrade rejects an invalid version" {
  local etc="$BATS_TEST_TMPDIR/etc"
  _seed_install "$etc" mysql
  run "$KCIMAGE" upgrade --keycloak-version bad --etc-dir "$etc"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid --keycloak-version"* ]]
}

@test "upgrade refuses Keycloak older than the 26 baseline" {
  local etc="$BATS_TEST_TMPDIR/etc"
  _seed_install "$etc" mysql
  run "$KCIMAGE" upgrade --keycloak-version 25.0.6 --etc-dir "$etc"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not supported"* ]]
  [[ "$output" == *"26.x or newer"* ]]
}

@test "upgrade refuses on a running (live) node" {
  export KIB_ASSUME_KEYCLOAK_ACTIVE=1
  run "$KCIMAGE" upgrade --keycloak-version 26.2.0 --etc-dir "$BATS_TEST_TMPDIR/etc"
  [ "$status" -ne 0 ]
  [[ "$output" == *"live node"* ]]
}

@test "upgrade does not accept --db-vendor (rejected as an unknown argument)" {
  local etc="$BATS_TEST_TMPDIR/etc"
  _seed_install "$etc" mysql
  run "$KCIMAGE" upgrade --keycloak-version 26.2.0 --db-vendor postgres --etc-dir "$etc"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown argument: --db-vendor"* ]]
}

@test "upgrade fails when there is no existing install" {
  run "$KCIMAGE" --dry-run upgrade --keycloak-version 26.2.0 --etc-dir "$BATS_TEST_TMPDIR/empty"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no existing install"* ]]
  [[ "$output" == *"install"* ]]
}

@test "dry-run upgrade derives the vendor from the model and activates+builds" {
  local etc="$BATS_TEST_TMPDIR/etc"
  _seed_install "$etc" mysql
  run "$KCIMAGE" --dry-run upgrade --keycloak-version 26.2.0 --etc-dir "$etc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"db=mysql"* ]]
  [[ "$output" == *"current -> keycloak-26.2.0"* ]]
  [[ "$output" == *"would write $etc/keycloak.conf (db=mysql)"* ]]
  [[ "$output" == *"kc.sh build"* ]]
}
