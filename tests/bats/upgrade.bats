#!/usr/bin/env bats
# upgrade — dry-run / validation only. The DB vendor is read from the model's
# keycloak.conf, never a flag, so an upgrade cannot change the baked vendor.
# The config dir is pointed at a temp dir via the KIB_CONF_DIR test hook.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  KCIMAGE="$REPO_ROOT/scripts/kcimage"
}

# A model with an existing install is simulated by a rendered keycloak.conf.
_seed_install() { # <conf-dir> <vendor>
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
  run env KIB_CONF_DIR="$etc" "$KCIMAGE" upgrade
  [ "$status" -ne 0 ]
  [[ "$output" == *"--keycloak-version is required"* ]]
}

@test "upgrade rejects an invalid version" {
  local etc="$BATS_TEST_TMPDIR/etc"
  _seed_install "$etc" mysql
  run env KIB_CONF_DIR="$etc" "$KCIMAGE" upgrade --keycloak-version bad
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid --keycloak-version"* ]]
}

@test "upgrade refuses Keycloak older than the 26 baseline" {
  local etc="$BATS_TEST_TMPDIR/etc"
  _seed_install "$etc" mysql
  run env KIB_CONF_DIR="$etc" "$KCIMAGE" upgrade --keycloak-version 25.0.6
  [ "$status" -ne 0 ]
  [[ "$output" == *"not supported"* ]]
  [[ "$output" == *"26.x or newer"* ]]
}

@test "upgrade refuses on a running (live) node" {
  export KIB_ASSUME_KEYCLOAK_ACTIVE=1
  run env KIB_CONF_DIR="$BATS_TEST_TMPDIR/etc" "$KCIMAGE" upgrade --keycloak-version 26.2.0
  [ "$status" -ne 0 ]
  [[ "$output" == *"live node"* ]]
}

@test "upgrade does not accept --db-vendor (rejected as an unknown argument)" {
  local etc="$BATS_TEST_TMPDIR/etc"
  _seed_install "$etc" mysql
  run env KIB_CONF_DIR="$etc" "$KCIMAGE" upgrade --keycloak-version 26.2.0 --db-vendor postgres
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown argument: --db-vendor"* ]]
}

@test "upgrade fails when there is no existing install" {
  run env KIB_CONF_DIR="$BATS_TEST_TMPDIR/empty" "$KCIMAGE" --dry-run upgrade --keycloak-version 26.2.0
  [ "$status" -ne 0 ]
  [[ "$output" == *"no existing install"* ]]
  [[ "$output" == *"install"* ]]
}

@test "dry-run upgrade derives the vendor, swaps the old aside, builds, and removes the previous version" {
  local etc="$BATS_TEST_TMPDIR/etc"
  _seed_install "$etc" mysql
  run env KIB_CONF_DIR="$etc" "$KCIMAGE" --dry-run upgrade --keycloak-version 26.2.0
  [ "$status" -eq 0 ]
  [[ "$output" == *"db=mysql"* ]]
  [[ "$output" == *"mv /opt/keycloak /opt/keycloak.bak"* ]]
  [[ "$output" == *"would write $etc/keycloak.conf (db=mysql)"* ]]
  [[ "$output" == *"kc.sh build"* ]]
  [[ "$output" == *"previous version removed"* ]]
  [[ "$output" != *"current ->"* ]]
}
