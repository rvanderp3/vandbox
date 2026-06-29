# Vandbox

Container-based sandbox for running untrusted workloads with seccomp, network, and binary allowlisting.

## Build & Run

```bash
make build           # Build base image
make run             # Build + run in enforce mode
make record          # Build + run in record mode (strace, generates seccomp profile)
make run-opencode    # Build + run OpenCode variant (requires GOOGLE_CLOUD_PROJECT)
make shell           # Build + run interactive shell (no security controls)
```

## Test & Lint

```bash
make test-network    # Test network allowlist enforcement
make test-binary     # Test binary allowlist enforcement
make lint            # Validate seccomp JSON files
```

## Architecture

The container entrypoint (`scripts/entrypoint.sh`) runs three setup phases as root before dropping to the `sandbox` user:

1. **Network** (`scripts/setup-network.sh`) — reads `config/network-allowlist.conf`, resolves hostnames, generates nftables rules, applies them, then disables `nft` itself
2. **Binaries** (`scripts/enforce-binaries.sh`) — reads `config/binary-allowlist.conf`, strips execute permission from all unlisted binaries in `/usr/bin`, `/usr/sbin`, `/usr/local/bin`
3. **Audit** (`scripts/audit-logger.sh`) — background poller that logs process starts/exits, network connections, file writes, and nftables denials to JSONL

All security setup happens at container start; the allowlist configs are bind-mounted read-only from the host.

## Key Files

- `Containerfile` — base image on UBI9, installs nftables
- `Containerfile.opencode` — extends base with git and OpenCode binary
- `run.sh` / `record.sh` / `run-opencode.sh` — launch scripts with podman flags
- `config/network-allowlist.conf` — `host:port` entries; `dns:53` enables DNS
- `config/binary-allowlist.conf` — absolute paths of allowed executables
- `seccomp/generate-profile.py` — parses strace logs into OCI seccomp profiles

## Conventions

- Shell scripts use `set -euo pipefail`
- Audit events are JSONL with `ts` and `event` fields
- Network allowlist format: `host:port`, `CIDR:port`, or `dns:53`
- Binary allowlist format: one absolute path per line
- The OpenCode variant has its own `config/opencode-*` allowlists
