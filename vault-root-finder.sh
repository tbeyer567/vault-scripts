#!/usr/bin/env bash
set -euo pipefail

# Finds Vault token accessors the have the "root" policy and prints a CSV.
# Requires:
#   - VAULT_ADDR and VAULT_TOKEN set (or equivalent Vault CLI auth)
#   - vault CI
#   - jq

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

# list out token accessors
accessors_json="$(vault list -format=json auth/token/accessors 2>/dev/null || true)"

if [[ -z "$accessors_json" || "$accessors_json" == "null" ]]; then
  echo "No accessors found (or you don't have permission to list token accessors)" >&2
  exit 0
fi

# output header
echo "=== Vault Root Tokens ==="

echo "$accessors_json" | jq -r '.[]' | while read -r accessor; do
  # loop through accessors and do a lookup
  lookup_json="$(vault token lookup -format=json -accessor "$accessor" 2>/dev/null || true)"
  if [[ -z "$lookup_json" || "$lookup_json" == "null" ]]; then
    continue
  fi

  # check if root policy is attached
  has_root="$(echo "$lookup_json" | jq -e '.data.policies[]? | index("root")' 2>/dev/null || true)"
  if [[ -z "$has_root" ]]; then
    continue
  fi

  # extract fields
  display_name="$(echo "$lookup_json" | jq -r '.data.display_name // ""')"
  creation_time="$(echo "$lookup_json" | jq -r '.data.creation_time // ""')"
  expire_time="$(echo "$lookup_json" | jq -r '.data.expire_time // "never"')"
  ttl_raw="$(echo "$lookup_json" | jq -r '.data.ttl // 0')"
  orphan="$(echo "$lookup_json" | jq -r '.data.orphan // false')"
  policies_str="$(echo "$lookup_json" | jq -r '.data.policies // [] | join(", ")')"

  # format TTL
  if [[ "$ttl_raw" == "0" ]]; then
    ttl="∞"
  else
    ttl="${ttl_raw}s"
  fi

  cat <<EOF
Accessor     : $accessor
Display Name : $display_name
Created      : $creation_time
Expires      : $expire_time
TTL          : $ttl
Orphan       : $orphan
Policies     : $policies_str
--------------------------------
EOF
done