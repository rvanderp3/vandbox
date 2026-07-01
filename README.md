# Vandbox

A container-based sandbox for running untrusted or experimental workloads. Two isolation models are available:

- **Base sandbox** — UBI9 containers with seccomp syscall filtering, nftables network allowlisting, binary execution allowlisting, and audit logging.
- **OpenCode sandbox** — Fedora 44 containers running inside [libkrun](https://github.com/containers/libkrun) microVMs with their own kernel. Paired with an MCP proxy stack for web search, code intelligence, and persistent memory.

## Prerequisites

- Podman
- Python 3 (for seccomp profile generation and lint)
- `crun-krun` and `/dev/kvm` (for OpenCode microVM sandbox): `dnf install crun-krun`
- `podman-compose` (for MCP stack): `dnf install podman-compose`

## Quick Start

### Base Sandbox

```bash
make build
make run           # Enforce mode (all security controls active)
make record        # Record mode (strace, generates seccomp profile)
make shell         # Interactive shell (no security controls)
```

The sandbox drops privileges to a `sandbox` user after initializing security controls. The `/workspace` directory is bind-mounted from the host for file exchange.

### OpenCode Sandbox (microVM)

```bash
# Start the MCP proxy stack (SearXNG, codebase-memory, fetch, memory)
make mcp-up

# Build and launch OpenCode in a microVM
export GOOGLE_CLOUD_PROJECT=your-project-id
make run-opencode
```

Each invocation creates an ephemeral microVM. Persistent state (sessions, config, installed tools) lives in `~/.opencode_sandbox_home` and survives across runs.

```bash
./run-opencode.sh bash      # Shell into a sandbox
./run-opencode.sh update    # Rebuild image with latest opencode
./run-opencode.sh help      # Show all subcommands
```

#### LLM Providers

Multiple providers can be configured simultaneously. OpenCode detects available credentials and offers them in the TUI.

| Provider | Configuration |
|---|---|
| Google Vertex AI | `GOOGLE_CLOUD_PROJECT` + `gcloud auth application-default login` |
| OpenAI-compatible (oMLX, LM Studio, etc.) | `OPENAI_API_KEY` + `OPENAI_BASE_URL` |
| Anthropic | `ANTHROPIC_API_KEY` |
| Custom providers | Add to `~/.opencode_sandbox_home/.config/opencode/opencode.jsonc` |

#### MCP Stack

The MCP proxy stack (`docker-compose.mcp.yml`) runs [mcpproxy-go](https://github.com/smart-mcp-proxy/mcpproxy-go) fronting four upstream MCP servers behind a single HTTP endpoint:

| Server | Tools | Purpose |
|---|---|---|
| [SearXNG](https://github.com/searxng/searxng) | 4 | Privacy-respecting metasearch (Google, DuckDuckGo, Bing, etc.) |
| [codebase-memory](https://github.com/DeusData/codebase-memory-mcp) | 14 | Code knowledge graph — 158 languages, sub-ms queries |
| [mcp-fetch](https://www.npmjs.com/package/mcp-fetch) | 5 | HTTP requests, URL fetching, HTML-to-markdown |
| [@modelcontextprotocol/server-memory](https://github.com/modelcontextprotocol/servers) | 9 | Persistent entity/relation knowledge graph |

```bash
make mcp-up        # Start the stack
make mcp-down      # Stop and remove
make mcp-logs      # Follow logs
```

The OpenCode sandbox auto-discovers the mcpproxy endpoint via `--add-host local-mcp:<IP>`. The mcpproxy web UI is available at `http://localhost:8888/ui/`.

## Base Sandbox Details

### Security Layers

- **Seccomp profiles** restrict which syscalls the container can make. A default profile is included; record mode generates a minimal profile from observed behavior.
- **Network allowlisting** uses nftables to drop all egress traffic except explicitly permitted host:port pairs. DNS resolution is gated separately.
- **Binary allowlisting** strips execute permission from every binary in `/usr/bin`, `/usr/sbin`, and `/usr/local/bin` that isn't on the allowlist.
- **Audit logging** polls `/proc` for new processes and network connections, logging events as JSONL to `/var/log/vandbox/audit.jsonl`.
- **Resource limits** cap memory, CPU, and PID count via Podman flags.

### Configuration

#### Environment Variables (Base Sandbox)

| Variable | Default | Description |
|---|---|---|
| `VANDBOX_IMAGE` | `vandbox:latest` | Container image to use |
| `VANDBOX_WORKSPACE` | `./workspace` | Host directory mounted to `/workspace` |
| `VANDBOX_AUDIT_DIR` | `./audit-logs` | Host directory for audit logs |
| `VANDBOX_SECCOMP` | `seccomp/default.json` | Seccomp profile path |
| `VANDBOX_NETWORK_CONF` | `config/network-allowlist.conf` | Network allowlist config |
| `VANDBOX_BINARY_CONF` | `config/binary-allowlist.conf` | Binary allowlist config |
| `VANDBOX_MEMORY` | `2g` | Memory limit |
| `VANDBOX_CPUS` | `2` | CPU limit |
| `VANDBOX_PIDS` | `256` | PID limit |

#### Environment Variables (OpenCode Sandbox)

| Variable | Default | Description |
|---|---|---|
| `OPENCODE_SANDBOX_IMAGE` | `vandbox:opencode` | Container image |
| `OPENCODE_SANDBOX_HOME` | `~/.opencode_sandbox_home` | Persistent home directory |
| `OPENCODE_SANDBOX_ALLOWED_DIR` | Current directory | Restrict mountable directories |
| `OPENCODE_SANDBOX_RAM` | `4096` | MicroVM RAM in MiB |
| `OPENCODE_SANDBOX_CPUS` | `4` | MicroVM vCPUs |
| `LOCAL_MCP_HOST` | Auto-detected | IP address for MCP proxy |

#### Network Allowlist (Base Sandbox)

Edit `config/network-allowlist.conf`. Format:

```
dns:53                          # Enable DNS to container's resolver
pypi.org:443                    # Hostname:port (resolved at startup)
10.0.0.0/8:443                  # CIDR:port
```

#### Binary Allowlist (Base Sandbox)

Edit `config/binary-allowlist.conf`. One absolute path per line.

### Record Mode

Runs with a permissive seccomp profile and strace attached. On exit, generates a minimal seccomp profile:

```bash
make record
# Generated profile saved to seccomp/generated.json
VANDBOX_SECCOMP=seccomp/generated.json ./run.sh
```

## Project Structure

```
.
├── Containerfile               # Base image (UBI9 + nftables)
├── Containerfile.opencode      # OpenCode image (Fedora 44 + opencode)
├── Containerfile.mcpproxy      # MCP proxy image (mcpproxy-go + Node.js)
├── docker-compose.mcp.yml      # MCP stack (SearXNG + mcpproxy)
├── Makefile                    # Build, run, test, lint, MCP targets
├── run.sh                      # Launch base sandbox (enforce mode)
├── record.sh                   # Launch base sandbox (record mode)
├── run-opencode.sh             # Launch OpenCode microVM sandbox
├── config/
│   ├── binary-allowlist.conf   # Base sandbox: allowed executables
│   ├── network-allowlist.conf  # Base sandbox: allowed network destinations
│   ├── searxng/settings.yml    # SearXNG configuration
│   └── mcpproxy/               # mcpproxy config (gitignored, runtime-generated)
├── scripts/
│   ├── entrypoint.sh           # Base sandbox: container init
│   ├── setup-network.sh        # Base sandbox: nftables rule generation
│   ├── enforce-binaries.sh     # Base sandbox: binary permission stripping
│   ├── audit-logger.sh         # Base sandbox: process/network polling
│   └── opencode-entrypoint.sh  # OpenCode: GCP credential setup + user switch
└── seccomp/
    ├── default.json            # Default seccomp profile
    ├── record.json             # Permissive profile for recording
    └── generate-profile.py     # Strace log -> seccomp profile
```

## Testing

```bash
make test-network    # Verify network restrictions (base sandbox)
make test-binary     # Verify binary restrictions (base sandbox)
make lint            # Validate seccomp JSON and configs
```

## Cleanup

```bash
make clean           # Remove images, workspace, audit logs, generated profiles
make mcp-down        # Stop MCP stack
```
