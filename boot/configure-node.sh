#!/usr/bin/env bash
# boot/configure-node.sh — ExecStart of keycloak-config.service (ADR-0005/0008).
# Baked into the AMI; runs once at boot as root, before keycloak.service.
#
# Config (incl. DB credentials) is delivered by launch-template user-data as
# KEY=VALUE lines using Keycloak's KC_* names (ADR-0008). This script:
#   1. reads this node's private IP from IMDSv2 (the JGroups bind address)
#   2. reads user-data from IMDSv2
#   3. routes each KEY=VALUE line:
#        secret keys  -> /run/keycloak/secrets.env  (tmpfs, 0640 root:keycloak)
#        everything else -> /etc/keycloak/keycloak.env
#
# No AWS CLI, no jq. Never logs secret values. Test hooks (skip IMDS): KIB_ETC,
# KIB_RUN, KIB_IMDS_BASE, KIB_USERDATA, NODE_PRIVATE_IP.
set -Eeuo pipefail

ETC="${KIB_ETC:-/etc/keycloak}"
RUN="${KIB_RUN:-/run/keycloak}"
IMDS_BASE="${KIB_IMDS_BASE:-http://169.254.169.254}"

# Keys routed to the tmpfs secrets file; everything else -> keycloak.env.
_is_secret_key() {
  case "$1" in
    KC_DB_USERNAME | KC_DB_PASSWORD | KC_BOOTSTRAP_ADMIN_USERNAME | KC_BOOTSTRAP_ADMIN_PASSWORD) return 0 ;;
    *) return 1 ;;
  esac
}

_imds_get() { # <token> <path>
  curl -sf -H "X-aws-ec2-metadata-token: $1" "$IMDS_BASE/latest/$2"
}

# --- gather inputs (env overrides win, so tests can skip IMDS) ---
imds_token=""
if [[ -z "${NODE_PRIVATE_IP:-}" || -z "${KIB_USERDATA:-}" ]]; then
  imds_token=$(curl -sf -X PUT "$IMDS_BASE/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 300") || {
    echo "keycloak-config: IMDSv2 token request failed" >&2
    exit 1
  }
fi

if [[ -z "${NODE_PRIVATE_IP:-}" ]]; then
  NODE_PRIVATE_IP=$(_imds_get "$imds_token" meta-data/local-ipv4) || {
    echo "keycloak-config: could not read local-ipv4 from IMDS" >&2
    exit 1
  }
fi

if [[ -z "${KIB_USERDATA:-}" ]]; then
  KIB_USERDATA=$(_imds_get "$imds_token" user-data) || {
    echo "keycloak-config: could not read user-data from IMDS" >&2
    exit 1
  }
fi

# --- prepare target files ---
mkdir -p "$ETC" "$RUN"
chmod 0750 "$RUN"
if [[ "$(id -u)" -eq 0 ]]; then
  chown root:keycloak "$RUN" 2> /dev/null || true
fi

env_file="$ETC/keycloak.env"
sec_file="$RUN/secrets.env"
umask 027
: > "$env_file"
: > "$sec_file"
chmod 0640 "$env_file" "$sec_file"
if [[ "$(id -u)" -eq 0 ]]; then
  chown root:keycloak "$sec_file" 2> /dev/null || true
fi

# JGroups bind address comes from IMDS, not user-data.
printf 'KC_CACHE_EMBEDDED_NETWORK_BIND_ADDRESS=%s\n' "$NODE_PRIVATE_IP" >> "$env_file"

# --- route user-data KEY=VALUE lines ---
have_db_url="" have_db_user="" have_db_pass="" have_hostname=""
while IFS= read -r line; do
  [[ "$line" =~ ^(KC_[A-Z0-9_]+|JAVA_OPTS_APPEND)= ]] || continue
  key=${line%%=*}
  val=${line#*=}
  if _is_secret_key "$key"; then
    printf '%s\n' "$line" >> "$sec_file"
  else
    printf '%s\n' "$line" >> "$env_file"
  fi
  [[ -n "$val" ]] || continue
  case "$key" in
    KC_DB_URL) have_db_url=1 ;;
    KC_DB_USERNAME) have_db_user=1 ;;
    KC_DB_PASSWORD) have_db_pass=1 ;;
    KC_HOSTNAME) have_hostname=1 ;;
  esac
done <<< "$KIB_USERDATA"

# --- validate required keys are present and non-empty ---
missing=()
[[ -n "$have_db_url" ]] || missing+=(KC_DB_URL)
[[ -n "$have_db_user" ]] || missing+=(KC_DB_USERNAME)
[[ -n "$have_db_pass" ]] || missing+=(KC_DB_PASSWORD)
[[ -n "$have_hostname" ]] || missing+=(KC_HOSTNAME)
if [[ ${#missing[@]} -gt 0 ]]; then
  echo "keycloak-config: user-data missing required keys: ${missing[*]}" >&2
  exit 1
fi

echo "keycloak-config: node configuration complete"
