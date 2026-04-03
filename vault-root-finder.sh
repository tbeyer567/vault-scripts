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
  if [[ -f "$_vault_token_file" || ! -s "$_vault_token_file" ]]; then
    echo "set VAULT_TOKEN environment variable or log in to Vault" >&2
    exit 1
  fi
fi

# list out token accessors
accessors_json="$(vault list -format=json auth/token/accessors 2>/dev/null || true)"

echo "$accessors_json" | jq -r '.[]'


