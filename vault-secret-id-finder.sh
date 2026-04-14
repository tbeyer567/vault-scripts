#!/usr/bin/env bash

set -euo pipefail

# This script finds AppRole secret-id's that were configured with problematic settings:
#   - Unlimited TTL (TTL = 0)
#   - Long TTL (TTL > 24 hours)
#   - Unlimited uses (num_uses = 0)
#   - High number of uses (num_uses > 10)
#
# Requires:
#   - VAULT_ADDR and VAULT_TOKEN set (or equivalent Vault CLI auth)
#   - vault CLI
#   - jq CLI
#
# TODO: add namespace support

if ! command -v vault >/dev/null 2>&1; then
  echo "vault CLI not found in PATH" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq not found in PATH" >&2
  exit 1
fi

if [[ -z "${VAULT_ADDR:-}" ]]; then
  echo "VAULT_ADDR environment variable is not set" >&2
  exit 1
fi

_vault_token_file="${HOME}/.vault-token"
if [[ -z "${VAULT_TOKEN:-}" ]]; then
  if [[ ! -f "$_vault_token_file" || ! -s "$_vault_token_file" ]]; then
    echo "set VAULT_TOKEN environment variable or log in to Vault" >&2
    exit 1
  fi
fi
unset _vault_token_file

# list out AppRole roles
roles_json="$(vault list -format=json auth/approle/role 2>/dev/null || true)"

if [[ -z "$roles_json" || "$roles_json" == "null" ]]; then
  echo "No AppRole roles found (or you don't have permission to list roles)" >&2
  exit 0
fi

# output header
echo "=== AppRole Secret-IDs with Problematic Settings ==="
echo

# 24 hours in seconds
ttl_threshold=86400
num_uses_threshold=10

echo "$roles_json" | jq -r '.[]?' | while read -r role; do
  # list secret-id accessors for this role
  accessors_json="$(vault list -format=json "auth/approle/role/${role}/secret-id" 2>/dev/null || true)"
  
  if [[ -z "$accessors_json" || "$accessors_json" == "null" ]]; then
    continue
  fi

  echo "$accessors_json" | jq -r '.[]?' | while read -r accessor; do
    # lookup secret-id metadata
    lookup_json="$(vault write -format=json "auth/approle/role/${role}/secret-id-accessor/lookup" accessor="$accessor" 2>/dev/null || true)"
    
    if [[ -z "$lookup_json" || "$lookup_json" == "null" ]]; then
      continue
    fi

    # extract fields
    ttl_raw="$(echo "$lookup_json" | jq -r '.data.secret_id_ttl // 0')"
    num_uses="$(echo "$lookup_json" | jq -r '.data.secret_id_num_uses // 0')"
    
    # check if TTL is 0 (unlimited) or > 24 hours, or num_uses is 0 (unlimited) or > 10
    if [[ "$ttl_raw" != "0" && "$ttl_raw" -le "$ttl_threshold" && "$num_uses" != "0" && "$num_uses" -le "$num_uses_threshold" ]]; then
      continue
    fi

    # extract additional fields
    creation_time="$(echo "$lookup_json" | jq -r '.data.creation_time // ""')"
    expiration_time="$(echo "$lookup_json" | jq -r '.data.expiration_time // "never"')"

    # format TTL and build reason
    reasons=()
    
    if [[ "$ttl_raw" == "0" ]]; then
      ttl="∞"
      reasons+=("Unlimited TTL")
    elif [[ "$ttl_raw" -gt "$ttl_threshold" ]]; then
      # Convert to human-readable format
      if [[ "$ttl_raw" -ge 86400 ]]; then
        days=$((ttl_raw / 86400))
        ttl="${days}d"
      elif [[ "$ttl_raw" -ge 3600 ]]; then
        hours=$((ttl_raw / 3600))
        ttl="${hours}h"
      else
        ttl="${ttl_raw}s"
      fi
      reasons+=("Long TTL (>24h)")
    else
      # TTL is acceptable, format it
      if [[ "$ttl_raw" -ge 3600 ]]; then
        hours=$((ttl_raw / 3600))
        ttl="${hours}h"
      else
        ttl="${ttl_raw}s"
      fi
    fi
    
    if [[ "$num_uses" == "0" ]]; then
      reasons+=("Unlimited uses")
    elif [[ "$num_uses" -gt "$num_uses_threshold" ]]; then
      reasons+=("High num_uses (>10)")
    fi
    
    # Join reasons with comma
    reason=$(IFS=", "; echo "${reasons[*]}")

    cat <<EOF
Role         : $role
Accessor     : $accessor
Created      : $creation_time
Expires      : $expiration_time
TTL          : $ttl
Reason       : $reason
Num Uses     : $num_uses
--------------------------------
EOF
  done
done

