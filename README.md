# vault-scripts

Small Bash utilities for [HashiCorp Vault](https://www.vaultproject.io/).

## Requirements

- [Vault CLI](https://developer.hashicorp.com/vault/docs/install)
- [jq](https://jqlang.org/)
- A Vault token with permission to run the operations each script needs

## Scripts

### `vault-root-finder.sh`

Lists token accessors that have the `root` or `hcp-root` policy by scanning `auth/token/accessors` and looking up each accessor.

**Environment**

- `VAULT_ADDR` — required
- `VAULT_TOKEN` — or a non-empty `~/.vault-token` after `vault login`
- `VAULT_NAMESPACE` — for HCP Vault Dedicated admin operations, set to `admin` (see Vault docs)

**Run**

```bash
chmod +x vault-root-finder.sh
./vault-root-finder.sh
```

You need policy rights to list accessors and look up tokens by accessor; otherwise the script may print nothing useful.

## License

MIT — see [LICENSE](LICENSE).