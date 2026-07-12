#!/usr/bin/env bash
# boot/configure-node.sh — ExecStart of keycloak-config.service (ADR-0005/0008).
# Baked into the AMI; runs once at boot as root, before keycloak.service.
#
# Flow (single JSON secret per cluster, ADR-0008):
#   1. read KDT_SECRET_ID (the cluster secret's name) from launch-template user-data
#   2. read this node's private IP from IMDSv2
#   3. fetch the one cluster secret from Secrets Manager (instance IAM role)
#   4. split it — non-secret fields -> /etc/keycloak/keycloak.env
#                 secret fields     -> /run/keycloak/secrets.env (tmpfs)
#
# Requires (model-instance prerequisites, baked into the AMI — see README):
#   - AWS CLI v2 (official bundle; not in the RHEL repos)
#   - jq (from dnf: `dnf install jq`)
#
# Never logs secret values. Test hooks (override to skip IMDS/AWS): KDT_ETC,
# KDT_RUN, KDT_IMDS_BASE, KDT_SECRET_ID, KDT_SECRET_JSON, NODE_PRIVATE_IP.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ETC="${KDT_ETC:-/etc/keycloak}"
RUN="${KDT_RUN:-/run/keycloak}"
IMDS_BASE="${KDT_IMDS_BASE:-http://169.254.169.254}"

# The env template sits beside this script when installed, or under ../templates
# when run from the repo/tarball.
TEMPLATE=""
for cand in "$SCRIPT_DIR/keycloak.env" "$SCRIPT_DIR/../templates/keycloak.env"; do
  [[ -f "$cand" ]] && {
    TEMPLATE="$cand"
    break
  }
done
[[ -n "$TEMPLATE" ]] || {
  echo "keycloak-config: keycloak.env template not found" >&2
  exit 1
}

_imds_get() { # <token> <path>
  curl -sf -H "X-aws-ec2-metadata-token: $1" "$IMDS_BASE/latest/$2"
}

# Extract KDT_SECRET_ID=<value> from user-data (optional 'export', optional quotes).
_secret_id_from_userdata() {
  local line
  line=$(grep -E '(^|[^[:alnum:]_])KDT_SECRET_ID=' <<< "$1" | tail -1 || true)
  line=${line#*KDT_SECRET_ID=}
  line=${line%%[[:space:]]*}
  line=${line#[\"\']}
  line=${line%[\"\']}
  printf '%s' "$line"
}

_field() { jq -r --arg k "$1" '.[$k] // ""' <<< "$KDT_SECRET_JSON"; }

_require() {
  [[ -n "$2" ]] || {
    echo "keycloak-config: secret missing required field: $1" >&2
    exit 1
  }
}

# --- gather inputs (env overrides win, so tests can skip IMDS/AWS) ---
imds_token=""
if [[ -z "${NODE_PRIVATE_IP:-}" || -z "${KDT_SECRET_JSON:-}" ]]; then
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
export NODE_PRIVATE_IP

if [[ -z "${KDT_SECRET_JSON:-}" ]]; then
  if [[ -z "${KDT_SECRET_ID:-}" ]]; then
    user_data=$(_imds_get "$imds_token" user-data || true)
    KDT_SECRET_ID=$(_secret_id_from_userdata "$user_data")
  fi
  [[ -n "${KDT_SECRET_ID:-}" ]] || {
    echo "keycloak-config: KDT_SECRET_ID not found in env or user-data" >&2
    exit 1
  }
  if [[ -z "${AWS_DEFAULT_REGION:-}" ]]; then
    AWS_DEFAULT_REGION=$(_imds_get "$imds_token" meta-data/placement/region) || {
      echo "keycloak-config: could not read region from IMDS" >&2
      exit 1
    }
    export AWS_DEFAULT_REGION
  fi
  KDT_SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id "$KDT_SECRET_ID" \
    --query SecretString --output text) || {
    echo "keycloak-config: secretsmanager get-secret-value failed" >&2
    exit 1
  }
fi

# --- unpack the cluster secret ---
db_url=$(_field db_url)
db_username=$(_field db_username)
db_password=$(_field db_password)
hostname=$(_field hostname)
java_opts=$(_field java_opts_append)
bootstrap_user=$(_field bootstrap_admin_username)
bootstrap_pass=$(_field bootstrap_admin_password)

_require db_url "$db_url"
_require db_username "$db_username"
_require db_password "$db_password"
_require hostname "$hostname"

# --- prepare target dirs ---
mkdir -p "$ETC" "$RUN"
chmod 0750 "$RUN"
if [[ "$(id -u)" -eq 0 ]]; then
  chown root:keycloak "$RUN" 2> /dev/null || true
fi

# --- non-secret runtime config -> /etc/keycloak/keycloak.env (via the template) ---
export KC_DB_URL="$db_url" KC_HOSTNAME="$hostname" JAVA_OPTS_APPEND="$java_opts"
# shellcheck disable=SC2016  # ${VARS} are envsubst's argument, not shell expansion
envsubst '${KC_DB_URL} ${KC_HOSTNAME} ${NODE_PRIVATE_IP} ${JAVA_OPTS_APPEND}' \
  < "$TEMPLATE" > "$ETC/keycloak.env"
chmod 0640 "$ETC/keycloak.env"

# --- secret values -> /run/keycloak/secrets.env (tmpfs, 0640 root:keycloak) ---
umask 027
{
  printf 'KC_DB_USERNAME=%s\n' "$db_username"
  printf 'KC_DB_PASSWORD=%s\n' "$db_password"
  if [[ -n "$bootstrap_user" && -n "$bootstrap_pass" ]]; then
    printf 'KC_BOOTSTRAP_ADMIN_USERNAME=%s\n' "$bootstrap_user"
    printf 'KC_BOOTSTRAP_ADMIN_PASSWORD=%s\n' "$bootstrap_pass"
  fi
} > "$RUN/secrets.env"
chmod 0640 "$RUN/secrets.env"
if [[ "$(id -u)" -eq 0 ]]; then
  chown root:keycloak "$RUN/secrets.env" 2> /dev/null || true
fi

echo "keycloak-config: node configuration complete"
