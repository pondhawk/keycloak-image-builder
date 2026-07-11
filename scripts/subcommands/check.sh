#!/usr/bin/env bash
# subcommand: check — read-only host prerequisite validation (blueprint §12).
# Answers "is this host capable of running KDT/Keycloak?". Deeper post-build
# functional checks live in 'verify' (ADR-0012).
# shellcheck shell=bash

_check_usage() {
  cat << EOF
Usage: kcadmin check [options]

Read-only prerequisite checks: Java, systemd, SELinux, DNS, required commands,
and (optionally) RDS TCP connectivity.

Options:
  --db-host <host>   Test TCP connectivity to the database host
  --db-port <port>   Database port (default: 3306 mysql / 5432 postgres)
  --dns-host <host>  Hostname to resolve for the DNS check
  -h, --help         Show this help
EOF
}

# _chk <PASS|FAIL|WARN|SKIP> <label> <detail>
_chk() {
  local status="$1" label="$2" detail="${3:-}"
  printf '[%-4s] %-9s %s\n' "$status" "$label" "$detail"
  case "$status" in
    PASS) CHK_PASS=$((CHK_PASS + 1)) ;;
    FAIL) CHK_FAIL=$((CHK_FAIL + 1)) ;;
    WARN) CHK_WARN=$((CHK_WARN + 1)) ;;
    SKIP) CHK_SKIP=$((CHK_SKIP + 1)) ;;
  esac
}

_check_java() {
  if command -v java > /dev/null 2>&1; then
    local v
    v="$(java -version 2>&1 | head -1)"
    if grep -qE "version \"${KDT_JAVA_MAJOR}([.\"]|$)" <<< "$v"; then
      _chk PASS Java "$v"
    else
      _chk FAIL Java "found, but not major ${KDT_JAVA_MAJOR}: $v"
    fi
  else
    _chk FAIL Java "java not found"
  fi
}

_check_systemd() {
  if [[ -d /run/systemd/system ]] && command -v systemctl > /dev/null 2>&1; then
    _chk PASS systemd "booted with systemd"
  else
    _chk FAIL systemd "host is not booted with systemd"
  fi
}

_check_selinux() {
  if command -v getenforce > /dev/null 2>&1; then
    local mode
    mode="$(getenforce 2> /dev/null || echo Unknown)"
    if [[ "$mode" == "Enforcing" ]]; then
      _chk PASS SELinux "Enforcing"
    else
      _chk FAIL SELinux "must be Enforcing (found: $mode) — ADR-0011"
    fi
  else
    _chk FAIL SELinux "getenforce not found; SELinux tooling missing"
  fi
}

_check_dns() {
  local host="$1"
  if getent hosts "$host" > /dev/null 2>&1; then
    _chk PASS DNS "resolved $host"
  else
    _chk FAIL DNS "could not resolve $host"
  fi
}

_check_commands() {
  local missing=() c
  for c in curl tar systemctl; do
    command -v "$c" > /dev/null 2>&1 || missing+=("$c")
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    _chk PASS commands "curl tar systemctl present"
  else
    _chk FAIL commands "missing: ${missing[*]}"
  fi
}

_check_rds() {
  local host="$1" port="$2"
  if [[ -z "$host" || -z "$port" ]]; then
    _chk SKIP RDS "no --db-host/--db-port given"
    return 0
  fi
  if timeout 5 bash -c "> /dev/tcp/$host/$port" 2> /dev/null; then
    _chk PASS RDS "reachable $host:$port"
  else
    _chk FAIL RDS "cannot connect to $host:$port"
  fi
}

cmd_check() {
  local db_host="" db_port="" dns_host=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --db-host)
        db_host="${2:-}"
        shift 2
        ;;
      --db-port)
        db_port="${2:-}"
        shift 2
        ;;
      --dns-host)
        dns_host="${2:-}"
        shift 2
        ;;
      -h | --help)
        _check_usage
        return 0
        ;;
      *)
        log_error "check: unknown argument: $1"
        _check_usage
        return "$EX_USAGE"
        ;;
    esac
  done

  # Default DNS target = the Keycloak download host.
  if [[ -z "$dns_host" ]]; then
    dns_host="${KEYCLOAK_DOWNLOAD_BASE#https://}"
    dns_host="${dns_host%%/*}"
  fi

  CHK_PASS=0 CHK_FAIL=0 CHK_WARN=0 CHK_SKIP=0
  _check_java
  _check_systemd
  _check_selinux
  _check_commands
  _check_dns "$dns_host"
  _check_rds "$db_host" "$db_port"

  printf 'checks: %d passed, %d failed, %d warnings, %d skipped\n' \
    "$CHK_PASS" "$CHK_FAIL" "$CHK_WARN" "$CHK_SKIP"
  [[ "$CHK_FAIL" -eq 0 ]] || return "$EX_CONFIG"
}
