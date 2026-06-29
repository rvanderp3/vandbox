# Vandbox

A container-based sandbox for running untrusted or experimental workloads with strict security controls. Vandbox uses Podman to launch UBI9-based containers with layered enforcement: seccomp syscall filtering, nftables network allowlisting, binary execution allowlisting, and continuous audit logging.

## Security Layers

- **Seccomp profiles** restrict which syscalls the container can make. A default profile is included; a record mode can generate a minimal profile from observed behavior.
- **Network allowlisting** uses nftables to drop all egress traffic except explicitly permitted host:port pairs. DNS resolution is gated separately.
- **Binary allowlisting** strips execute permission from every binary in `/usr/bin`, `/usr/sbin`, and `/usr/local/bin` that isn't on the allowlist.
- **Audit logging** polls `/proc` for new processes and network connections, logging events as JSONL to `/var/log/vandbox/audit.jsonl`.
- **Resource limits** cap memory, CPU, and PID count via Podman flags.

## Prerequisites

- Podman
- Python 3 (for seccomp profile generation and lint)

## Quick Start

```bash
# Build and run (enforce mode)
make run

# Or build separately
make build
./run.sh
```

The sandbox drops privileges to a `sandbox` user after initializing security controls. The `/workspace` directory is bind-mounted from the host for file exchange.

## Modes

### Enforce (default)

Runs with all security controls active. Blocked network traffic and stripped binaries are logged.

```bash
make run
# or
./run.sh
```

### Record

Runs with a permissive seccomp profile and strace attached. On exit, generates a minimal seccomp profile based on observed syscalls.

```bash
make record
# or
./record.sh
```

The generated profile is saved to `seccomp/generated.json`. Use it in enforce mode:

```bash
VANDBOX_SECCOMP=seccomp/generated.json ./run.sh
```

### OpenCode

Extends the base image with [OpenCode](https://github.com/anomalyco/opencode) and git. Uses Google Vertex AI for LLM access, so it requires GCP credentials.

```bash
export GOOGLE_CLOUD_PROJECT=your-project-id
gcloud auth application-default login
make run-opencode
```

## Configuration

### Environment Variables

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

### Network Allowlist

Edit `config/network-allowlist.conf`. Format:

```
dns:53                          # Enable DNS to container's resolver
pypi.org:443                    # Hostname:port (resolved at startup)
10.0.0.0/8:443                  # CIDR:port
```

### Binary Allowlist

Edit `config/binary-allowlist.conf`. One absolute path per line. Shebang interpreters for allowed scripts are auto-detected and permitted.

## Project Structure

```
.
├── Containerfile               # Base image (UBI9 + nftables)
├── Containerfile.opencode      # OpenCode layer (git + opencode binary)
├── Makefile                    # Build, run, test, lint targets
├── run.sh                      # Launch in enforce mode
├── record.sh                   # Launch in record mode (strace)
├── run-opencode.sh             # Launch OpenCode sandbox
├── config/
│   ├── binary-allowlist.conf   # Allowed executables
│   ├── network-allowlist.conf  # Allowed network destinations
│   ├── opencode-binary-allowlist.conf
│   └── opencode-network-allowlist.conf
├── scripts/
│   ├── entrypoint.sh           # Container init (orchestrates setup)
│   ├── setup-network.sh        # nftables rule generation
│   ├── enforce-binaries.sh     # Binary permission stripping
│   ├── audit-logger.sh         # Process/network/file polling
│   └── opencode-entrypoint.sh  # GCP credential setup wrapper
└── seccomp/
    ├── default.json            # Default seccomp profile
    ├── record.json             # Permissive profile for recording
    └── generate-profile.py     # Strace log -> seccomp profile
```

## Testing

```bash
make test-network    # Verify network restrictions
make test-binary     # Verify binary restrictions
make lint            # Validate seccomp JSON and configs
```

## Cleanup

```bash
make clean           # Remove images, workspace, audit logs, generated profiles
```
