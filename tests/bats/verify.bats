#!/usr/bin/env bats
# verify — structure + the deterministic config/units checks (via overrides).

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  KCIMAGE="$REPO_ROOT/scripts/kcimage"
}

@test "verify --help exits 0" {
  run "$KCIMAGE" verify --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Validate that KIB provisioned"* ]]
}

@test "verify reports all items and a summary" {
  run "$KCIMAGE" verify
  [[ "$output" == *"Java"* ]]
  [[ "$output" == *"install"* ]]
  [[ "$output" == *"config"* ]]
  [[ "$output" == *"SELinux"* ]]
  [[ "$output" == *"units"* ]]
  [[ "$output" == *"checks:"* ]]
}

@test "verify passes config with a rendered keycloak.conf" {
  local etc="$BATS_TEST_TMPDIR/etc"
  mkdir -p "$etc"
  printf 'db=mysql\n' > "$etc/keycloak.conf"
  run env KIB_CONF_DIR="$etc" "$KCIMAGE" verify
  [[ "$output" == *"[PASS] config"* ]]
}

@test "verify passes units when unit files are present" {
  local sd="$BATS_TEST_TMPDIR/sd"
  mkdir -p "$sd"
  touch "$sd/keycloak.service" "$sd/keycloak-config.service"
  run env KIB_SYSTEMD_DIR="$sd" "$KCIMAGE" verify
  [[ "$output" == *"[PASS] units"* ]]
}

@test "verify passes providers when every custom JAR is deployed" {
  local pdir="$BATS_TEST_TMPDIR/prov" home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$pdir" "$home/providers"
  echo x > "$pdir/foo.jar"
  echo x > "$home/providers/foo.jar"
  run env KIB_HOME="$home" "$KCIMAGE" verify --providers-dir "$pdir"
  [[ "$output" == *"[PASS] providers"* ]]
}

@test "verify fails providers when a custom JAR is missing from the install" {
  local pdir="$BATS_TEST_TMPDIR/prov" home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$pdir" "$home/providers"
  echo x > "$pdir/foo.jar"   # never copied to the install
  run env KIB_HOME="$home" "$KCIMAGE" verify --providers-dir "$pdir"
  [[ "$output" == *"[FAIL] providers"* ]]
  [[ "$output" == *"foo.jar"* ]]
}

@test "verify skips providers when the providers dir is empty" {
  local pdir="$BATS_TEST_TMPDIR/prov"
  mkdir -p "$pdir"
  run "$KCIMAGE" verify --providers-dir "$pdir"
  [[ "$output" == *"[SKIP] providers"* ]]
}
