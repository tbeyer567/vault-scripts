#!/usr/bin/env bash
set -euo pipefail

# Finds Vault token accessors the have the "root" policy and prints a CSV.
# Requires:
#   - VAULT_ADDR and VAULT_TOKEN set (or equivalent Vault CLI auth)
#   - vault CI
#   - jq


