#!/usr/bin/env bats
# verify — structure + the deterministic config/units checks (via overrides).

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  KCADMIN="$REPO_ROOT/scripts/kcadmin"
}

@test "verify --help exits 0" {
  run "$KCADMIN" verify --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Validate that KDT provisioned"* ]]
}

@test "verify reports all items and a summary" {
  run "$KCADMIN" verify
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
  run "$KCADMIN" verify --etc-dir "$etc"
  [[ "$output" == *"[PASS] config"* ]]
}

@test "verify passes units when unit files are present" {
  local sd="$BATS_TEST_TMPDIR/sd"
  mkdir -p "$sd"
  touch "$sd/keycloak.service" "$sd/keycloak-config.service"
  run "$KCADMIN" verify --systemd-dir "$sd"
  [[ "$output" == *"[PASS] units"* ]]
}
