#!/usr/bin/env bats
# install — dry-run / validation only (never a real install; safe under any user).

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  KCADMIN="$REPO_ROOT/scripts/kcadmin"
}

@test "install requires --keycloak-version" {
  run "$KCADMIN" install --db-vendor mysql
  [ "$status" -ne 0 ]
  [[ "$output" == *"--keycloak-version is required"* ]]
}

@test "install requires --db-vendor" {
  run "$KCADMIN" install --keycloak-version 26.1.4
  [ "$status" -ne 0 ]
  [[ "$output" == *"--db-vendor is required"* ]]
}

@test "install rejects an invalid version" {
  run "$KCADMIN" install --keycloak-version bad --db-vendor mysql
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid --keycloak-version"* ]]
}

@test "install rejects an invalid vendor" {
  run "$KCADMIN" install --keycloak-version 26.1.4 --db-vendor oracle
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid --db-vendor"* ]]
}

@test "install --help exits 0" {
  run "$KCADMIN" install --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"prepare it for imaging"* ]]
}

@test "dry-run install plans dist, config render, and build" {
  run "$KCADMIN" --dry-run install --keycloak-version 26.1.4 --db-vendor mysql --etc-dir "$BATS_TEST_TMPDIR/etc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run]"* ]]
  [[ "$output" == *"would write $BATS_TEST_TMPDIR/etc/keycloak.conf (db=mysql)"* ]]
  [[ "$output" == *"kc.sh build"* ]]
  [[ "$output" == *"install complete"* ]]
}

@test "dry-run install creates nothing" {
  run "$KCADMIN" --dry-run install --keycloak-version 26.1.4 --db-vendor postgres --etc-dir "$BATS_TEST_TMPDIR/etc"
  [ "$status" -eq 0 ]
  [ ! -e /opt/keycloak/keycloak-26.1.4 ]
  [ ! -f "$BATS_TEST_TMPDIR/etc/keycloak.conf" ]
}
