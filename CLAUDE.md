# Vandbox

Container-based sandbox for running untrusted workloads. Two isolation models: base (seccomp/nftables) and OpenCode (libkrun microVM).

## Build & Run

```bash
make build           # Build base image (seccomp/nftables sandbox)
make run             # Build + run base in enforce mode
make record          # Build + run in record mode (strace, generates seccomp profile)
make shell           # Build + run interactive shell (no security controls)
```

### OpenCode Sandbox (microVM)

Requires `crun-krun` and `/dev/kvm` on the host (`dnf install crun-krun`).

```bash
make mcp-up                 # Start MCP stack (SearXNG + mcpproxy + tools)
make build-opencode         # Build OpenCode image (Fedora 44 + opencode)
make run-opencode           # Build + launch OpenCode in microVM sandbox
./run-opencode.sh bash      # Shell into the running sandbox
./run-opencode.sh update    # Rebuild image with latest opencode
./run-opencode.sh help      # Show all subcommands
```

### MCP Stack

```bash
make mcp-up          # Start SearXNG + mcpproxy (4 upstream MCP servers)
make mcp-down        # Stop the stack
make mcp-logs        # Follow logs
```

Upstream servers: SearXNG (search), codebase-memory (code knowledge graph), mcp-fetch (URL fetching), server-memory (persistent entity store). All exposed as direct tools via mcpproxy at `http://local-mcp:8888/mcp`.

### Environment Variables (OpenCode)

- `GOOGLE_CLOUD_PROJECT` — GCP project ID for Vertex AI
- `VERTEX_LOCATION` — Vertex AI region (default: `global`)
- `GCLOUD_ADC_FILE` — path to ADC credentials (default: `~/.config/gcloud/application_default_credentials.json`)
- `OPENAI_API_KEY` / `OPENAI_BASE_URL` — OpenAI-compatible provider (oMLX, LM Studio, etc.)
- `ANTHROPIC_API_KEY` — direct Anthropic API access
- `OPENCODE_SANDBOX_HOME` — persistent home directory (default: `~/.opencode_sandbox_home`)
- `OPENCODE_SANDBOX_ALLOWED_DIR` — restrict which directories can be mounted (default: current directory)
- `OPENCODE_SANDBOX_RAM` — microVM RAM in MiB (default: `4096`)
- `OPENCODE_SANDBOX_CPUS` — microVM vCPUs (default: `4`)
- `LOCAL_MCP_HOST` — override MCP proxy IP (default: auto-detected)

## Test & Lint

```bash
make test-network    # Test network allowlist enforcement (base image)
make test-binary     # Test binary allowlist enforcement (base image)
make lint            # Validate seccomp JSON files
```

## Architecture

### Base Sandbox (Containerfile)

The base container entrypoint (`scripts/entrypoint.sh`) runs three setup phases as root before dropping to the `sandbox` user:

1. **Network** (`scripts/setup-network.sh`) — reads `config/network-allowlist.conf`, resolves hostnames, generates nftables rules
2. **Binaries** (`scripts/enforce-binaries.sh`) — reads `config/binary-allowlist.conf`, strips execute permission from unlisted binaries
3. **Audit** (`scripts/audit-logger.sh`) — background poller that logs process starts/exits, network connections, file writes to JSONL

### OpenCode Sandbox (Containerfile.opencode)

Each invocation runs inside a **libkrun microVM** with its own kernel. No seccomp/nftables/binary allowlisting — the VM boundary provides isolation.

- `Containerfile.opencode` — standalone Fedora 44 image with git and opencode
- `run-opencode.sh` — ephemeral `podman run` per session with krun annotations, persistent home via volume mount, auto-discovers MCP proxy
- `scripts/opencode-entrypoint.sh` — handles krun root-boot, GCP ADC credential setup, drops to `opencode` user

### MCP Stack (docker-compose.mcp.yml)

mcpproxy-go fronts 4 MCP servers behind a single HTTP endpoint in direct routing mode:

- `config/searxng/settings.yml` — SearXNG config (JSON format enabled, secret via `.env`)
- `config/mcpproxy/` — mcpproxy runtime config (gitignored, contains API key)
- `Containerfile.mcpproxy` — mcpproxy image with Node.js for stdio MCP servers
- Host code directory mounted read-only for codebase-memory indexing

## Key Files

- `Containerfile` — base image on UBI9, installs nftables
- `Containerfile.opencode` — standalone Fedora 44 image with opencode (microVM)
- `Containerfile.mcpproxy` — mcpproxy-go with Node.js for stdio MCP servers
- `docker-compose.mcp.yml` — MCP stack (SearXNG + mcpproxy)
- `run.sh` / `record.sh` — launch scripts for base sandbox
- `run-opencode.sh` — launch OpenCode microVM sandbox
- `.env` — secrets (gitignored)

## Conventions

- Shell scripts use `set -euo pipefail`
- Audit events are JSONL with `ts` and `event` fields
- Network allowlist format: `host:port`, `CIDR:port`, or `dns:53`
- Binary allowlist format: one absolute path per line
- Secrets go in `.env` (gitignored), never in tracked config files
