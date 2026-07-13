#!/usr/bin/env bats
# install — dry-run / validation only (never a real install; safe under any user).

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  KCIMAGE="$REPO_ROOT/scripts/kcimage"
}

@test "install requires --keycloak-version" {
  run "$KCIMAGE" install --db-vendor mysql
  [ "$status" -ne 0 ]
  [[ "$output" == *"--keycloak-version is required"* ]]
}

@test "install requires --db-vendor" {
  run "$KCIMAGE" install --keycloak-version 26.1.4
  [ "$status" -ne 0 ]
  [[ "$output" == *"--db-vendor is required"* ]]
}

@test "install rejects an invalid version" {
  run "$KCIMAGE" install --keycloak-version bad --db-vendor mysql
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid --keycloak-version"* ]]
}

@test "install refuses Keycloak older than the 26 baseline" {
  run "$KCIMAGE" install --keycloak-version 25.0.6 --db-vendor mysql
  [ "$status" -ne 0 ]
  [[ "$output" == *"not supported"* ]]
  [[ "$output" == *"26.x or newer"* ]]
}

@test "install refuses on a running (live) node" {
  export KIB_ASSUME_KEYCLOAK_ACTIVE=1
  run "$KCIMAGE" install --keycloak-version 26.1.4 --db-vendor mysql
  [ "$status" -ne 0 ]
  [[ "$output" == *"live node"* ]]
}

@test "install rejects an invalid vendor" {
  run "$KCIMAGE" install --keycloak-version 26.1.4 --db-vendor oracle
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid --db-vendor"* ]]
}

@test "install --help exits 0" {
  run "$KCIMAGE" install --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"prepare it for imaging"* ]]
}

@test "keycloak.service recreates the data StateDirectory (keycloak#31949 gzip cache)" {
  grep -qxE 'StateDirectory=keycloak/data' "$REPO_ROOT/systemd/keycloak.service"
}

@test "dry-run install plans dist, config render, and build" {
  run "$KCIMAGE" --dry-run install --keycloak-version 26.1.4 --db-vendor mysql --etc-dir "$BATS_TEST_TMPDIR/etc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run]"* ]]
  [[ "$output" == *"would write $BATS_TEST_TMPDIR/etc/keycloak.conf (db=mysql)"* ]]
  [[ "$output" == *"kc.sh build"* ]]
  [[ "$output" == *"enable keycloak-config.service"* ]]
  [[ "$output" == *"install complete"* ]]
}

@test "dry-run install (default) activates and builds" {
  run "$KCIMAGE" --dry-run install --keycloak-version 26.1.4 --db-vendor postgres --etc-dir "$BATS_TEST_TMPDIR/etc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"current -> keycloak-26.1.4"* ]]
  [[ "$output" == *"kc.sh build"* ]]
}

@test "install refuses when the model already has an install (greenfield-only)" {
  local etc="$BATS_TEST_TMPDIR/etc"
  mkdir -p "$etc"
  printf 'db=mysql\n' > "$etc/keycloak.conf"
  run "$KCIMAGE" --dry-run install --keycloak-version 26.1.4 --db-vendor postgres --etc-dir "$etc"
  [ "$status" -ne 0 ]
  [[ "$output" == *"already installed"* ]]
  [[ "$output" == *"upgrade"* ]]
}

@test "dry-run install creates nothing" {
  run "$KCIMAGE" --dry-run install --keycloak-version 26.1.4 --db-vendor postgres --etc-dir "$BATS_TEST_TMPDIR/etc"
  [ "$status" -eq 0 ]
  [ ! -e /opt/keycloak/keycloak-26.1.4 ]
  [ ! -f "$BATS_TEST_TMPDIR/etc/keycloak.conf" ]
}
