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

@test "install rejects an invalid --arch value" {
  run "$KCIMAGE" --dry-run install --keycloak-version 26.1.4 --db-vendor mysql --arch sparc
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid --arch"* ]]
}

@test "install --arch matching the host is accepted; the other arch is refused" {
  local match other
  case "$(uname -m)" in
    x86_64 | amd64) match=x64 other=arm64 ;;
    aarch64 | arm64) match=arm64 other=x64 ;;
    *) skip "unsupported test host arch: $(uname -m)" ;;
  esac
  run env KIB_CONF_DIR="$BATS_TEST_TMPDIR/etc" "$KCIMAGE" --dry-run install --keycloak-version 26.1.4 --db-vendor mysql --arch "$match"
  [ "$status" -eq 0 ]
  run env KIB_CONF_DIR="$BATS_TEST_TMPDIR/etc" "$KCIMAGE" --dry-run install --keycloak-version 26.1.4 --db-vendor mysql --arch "$other"
  [ "$status" -ne 0 ]
  [[ "$output" == *"cross-build"* ]]
}

@test "install --help exits 0" {
  run "$KCIMAGE" install --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"prepare it for imaging"* ]]
}

@test "keycloak.service has no read-only sandbox fighting Keycloak's data writes" {
  # Keycloak owns and writes KEYCLOAK_HOME/data in place; ProtectSystem=strict
  # (and its symlink/StateDirectory workarounds) must not come back.
  ! grep -qE '^(ProtectSystem=strict|StateDirectory=)' "$REPO_ROOT/systemd/keycloak.service"
}

@test "dry-run install plans dist, config render, and build" {
  run env KIB_CONF_DIR="$BATS_TEST_TMPDIR/etc" "$KCIMAGE" --dry-run install --keycloak-version 26.1.4 --db-vendor mysql
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run]"* ]]
  [[ "$output" == *"would write $BATS_TEST_TMPDIR/etc/keycloak.conf (db=mysql)"* ]]
  [[ "$output" == *"kc.sh build"* ]]
  [[ "$output" == *"enable keycloak-config.service"* ]]
  [[ "$output" == *"install complete"* ]]
}

@test "dry-run install extracts straight to /opt/keycloak (no versioned dir)" {
  run env KIB_CONF_DIR="$BATS_TEST_TMPDIR/etc" "$KCIMAGE" --dry-run install --keycloak-version 26.1.4 --db-vendor postgres
  [ "$status" -eq 0 ]
  [[ "$output" == *"extract to /opt/keycloak"* ]]
  [[ "$output" != *"current ->"* ]]
  [[ "$output" == *"kc.sh build"* ]]
}

@test "install refuses when the model already has an install (greenfield-only)" {
  local etc="$BATS_TEST_TMPDIR/etc"
  mkdir -p "$etc"
  printf 'db=mysql\n' > "$etc/keycloak.conf"
  run env KIB_CONF_DIR="$etc" "$KCIMAGE" --dry-run install --keycloak-version 26.1.4 --db-vendor postgres
  [ "$status" -ne 0 ]
  [[ "$output" == *"already installed"* ]]
  [[ "$output" == *"clean"* ]]
}

@test "dry-run install creates nothing" {
  run env KIB_CONF_DIR="$BATS_TEST_TMPDIR/etc" "$KCIMAGE" --dry-run install --keycloak-version 26.1.4 --db-vendor postgres
  [ "$status" -eq 0 ]
  [ ! -e /opt/keycloak/keycloak-26.1.4 ]
  [ ! -f "$BATS_TEST_TMPDIR/etc/keycloak.conf" ]
}
