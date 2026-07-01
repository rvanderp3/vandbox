# Vandbox

Container-based sandbox for running untrusted workloads.

## Build & Run

```bash
make build           # Build base image (seccomp/nftables sandbox)
make run             # Build + run base in enforce mode
make record          # Build + run in record mode (strace, generates seccomp profile)
make shell           # Build + run interactive shell (no security controls)
```

### OpenCode Sandbox (microVM)

The OpenCode variant uses libkrun microVMs for isolation instead of seccomp/nftables.
Requires `crun-krun` and `/dev/kvm` on the host (`dnf install crun-krun`).

```bash
make build-opencode         # Build OpenCode image (Fedora 44 + opencode)
make run-opencode           # Build + launch OpenCode in microVM sandbox
make opencode-down          # Stop and remove the sandbox container
./run-opencode.sh bash      # Shell into the running sandbox
./run-opencode.sh update    # Update opencode binary inside sandbox
./run-opencode.sh help      # Show all subcommands
```

Environment variables for OpenCode sandbox:
- `GOOGLE_CLOUD_PROJECT` — GCP project ID for Vertex AI (required for GCP auth)
- `VERTEX_LOCATION` — Vertex AI region (default: `global`)
- `GCLOUD_ADC_FILE` — path to ADC credentials (default: `~/.config/gcloud/application_default_credentials.json`)
- `OPENCODE_SANDBOX_HOME` — persistent home directory (default: `~/.opencode_sandbox_home`)
- `OPENCODE_SANDBOX_ALLOWED_DIR` — restrict which directories can be mounted (default: current directory)
- `OPENCODE_SANDBOX_RAM` — microVM RAM in MiB (default: `4096`)
- `OPENCODE_SANDBOX_CPUS` — microVM vCPUs (default: `4`)

## Test & Lint

```bash
make test-network    # Test network allowlist enforcement (base image)
make test-binary     # Test binary allowlist enforcement (base image)
make lint            # Validate seccomp JSON files
```

## Architecture

### Base Sandbox (Containerfile)

The base container entrypoint (`scripts/entrypoint.sh`) runs three setup phases as root before dropping to the `sandbox` user:

1. **Network** (`scripts/setup-network.sh`) — reads `config/network-allowlist.conf`, resolves hostnames, generates nftables rules, applies them, then disables `nft` itself
2. **Binaries** (`scripts/enforce-binaries.sh`) — reads `config/binary-allowlist.conf`, strips execute permission from all unlisted binaries in `/usr/bin`, `/usr/sbin`, `/usr/local/bin`
3. **Audit** (`scripts/audit-logger.sh`) — background poller that logs process starts/exits, network connections, file writes, and nftables denials to JSONL

### OpenCode Sandbox (Containerfile.opencode)

Uses a fundamentally different isolation model: each container runs inside a **libkrun microVM** with its own kernel. No seccomp profiles, network allowlists, or binary allowlists needed — the VM boundary provides isolation.

- `Containerfile.opencode` — standalone Fedora 44 image with git and opencode
- `run-opencode.sh` — lifecycle script: creates a long-running container in a microVM, reuses it across sessions via `podman exec`
- `scripts/opencode-entrypoint.sh` — handles krun root-boot behavior, sets up GCP credentials, drops to `opencode` user
- Persistent state lives in `~/.opencode_sandbox_home` (survives container restarts)

## Key Files

- `Containerfile` — base image on UBI9, installs nftables
- `Containerfile.opencode` — standalone Fedora 44 image with opencode (microVM)
- `run.sh` / `record.sh` — launch scripts for base sandbox
- `run-opencode.sh` — lifecycle management for OpenCode microVM sandbox
- `config/network-allowlist.conf` — `host:port` entries; `dns:53` enables DNS (base sandbox)
- `config/binary-allowlist.conf` — absolute paths of allowed executables (base sandbox)
- `seccomp/generate-profile.py` — parses strace logs into OCI seccomp profiles

## Conventions

- Shell scripts use `set -euo pipefail`
- Audit events are JSONL with `ts` and `event` fields
- Network allowlist format: `host:port`, `CIDR:port`, or `dns:53`
- Binary allowlist format: one absolute path per line
