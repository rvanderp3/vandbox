#!/bin/bash
set -euo pipefail

if [[ "${1:-}" = "help" ]]; then
    echo "opencode sandbox (podman + libkrun microVM)"
    echo "Usage: ./run-opencode.sh [command] [args]"
    echo
    echo "Commands:"
    echo "  help    Show this help message."
    echo "  bash    Start a bash session inside the sandbox."
    echo "  update  Rebuild the image with the latest opencode."
    echo "  (none)  Run opencode inside the sandbox (default)."
    echo
    exit 0
fi

CURRENT_DIR=$(pwd)

OPENCODE_SANDBOX_ALLOWED_DIR=${OPENCODE_SANDBOX_ALLOWED_DIR:-$CURRENT_DIR}

if [[ "$CURRENT_DIR" != "$OPENCODE_SANDBOX_ALLOWED_DIR"* ]]; then
    echo "Error: must be run inside '${OPENCODE_SANDBOX_ALLOWED_DIR}'"
    exit 1
fi

OPENCODE_SANDBOX_IMAGE=${OPENCODE_SANDBOX_IMAGE:-vandbox:opencode}
OPENCODE_SANDBOX_HOME=${OPENCODE_SANDBOX_HOME:-${HOME}/.opencode_sandbox_home}
OPENCODE_SANDBOX_RAM=${OPENCODE_SANDBOX_RAM:-4096}
OPENCODE_SANDBOX_CPUS=${OPENCODE_SANDBOX_CPUS:-4}

GOOGLE_CLOUD_PROJECT="${GOOGLE_CLOUD_PROJECT:-}"
VERTEX_LOCATION="${VERTEX_LOCATION:-global}"
GCLOUD_ADC_FILE="${GCLOUD_ADC_FILE:-${HOME}/.config/gcloud/application_default_credentials.json}"

OPENAI_API_KEY="${OPENAI_API_KEY:-}"
OPENAI_BASE_URL="${OPENAI_BASE_URL:-}"
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"

LOCAL_MCP_HOST="${LOCAL_MCP_HOST:-}"

TZ=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "UTC")

# Resolve local-mcp hostname: check if mcpproxy compose stack is running
if [ -z "${LOCAL_MCP_HOST}" ]; then
    MCPPROXY_IP=$(podman inspect vandbox-mcpproxy --format '{{.NetworkSettings.IPAddress}}' 2>/dev/null || true)
    if [ -z "${MCPPROXY_IP}" ]; then
        # Fall back to host gateway (mcpproxy is on host port 8888)
        MCPPROXY_IP=$(ip -4 route show default | awk '{print $3; exit}' 2>/dev/null || true)
    fi
    LOCAL_MCP_HOST="${MCPPROXY_IP:-}"
fi

# Seed persistent home from container defaults on first run
if [ ! -d "$OPENCODE_SANDBOX_HOME" ]; then
    echo "Creating sandbox home: ${OPENCODE_SANDBOX_HOME} ..."
    mkdir -p "$OPENCODE_SANDBOX_HOME"
    podman run --rm \
        -v "${OPENCODE_SANDBOX_HOME}:/sandbox_home:U" \
        "${OPENCODE_SANDBOX_IMAGE}" sh -c "cp -a /home/opencode/. /sandbox_home/"
fi

if [[ "${1:-}" = "update" ]]; then
    echo "Rebuilding image with latest opencode..."
    podman build -f Containerfile.opencode \
        --build-arg HOST_UID="$(id -u)" \
        --build-arg HOST_GID="$(id -g)" \
        --no-cache \
        -t "${OPENCODE_SANDBOX_IMAGE}" .
    echo "Done. Run ./run-opencode.sh to start."
    exit 0
fi

CMD="opencode"
PARAMS=("$@")

if [[ "${1:-}" = "bash" ]]; then
    CMD="bash"
    PARAMS=()
fi

PROVIDER_MOUNTS=()
PROVIDER_ENV=()
if [ -n "${GOOGLE_CLOUD_PROJECT}" ] && [ -f "${GCLOUD_ADC_FILE}" ]; then
    PROVIDER_MOUNTS+=(-v "${GCLOUD_ADC_FILE}:/mnt/gcloud-adc/application_default_credentials.json:z")
    PROVIDER_ENV+=(-e "GOOGLE_CLOUD_PROJECT=${GOOGLE_CLOUD_PROJECT}" -e "VERTEX_LOCATION=${VERTEX_LOCATION}")
fi
[ -n "${OPENAI_API_KEY}" ]    && PROVIDER_ENV+=(-e "OPENAI_API_KEY=${OPENAI_API_KEY}")
[ -n "${OPENAI_BASE_URL}" ]   && PROVIDER_ENV+=(-e "OPENAI_BASE_URL=${OPENAI_BASE_URL}")
[ -n "${ANTHROPIC_API_KEY}" ] && PROVIDER_ENV+=(-e "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}")

echo "Running ${CMD} in microVM sandbox"
echo "  workspace: ${OPENCODE_SANDBOX_ALLOWED_DIR}"
echo "  home:      ${OPENCODE_SANDBOX_HOME}"
echo "  ram:       ${OPENCODE_SANDBOX_RAM}MiB"
echo "  cpus:      ${OPENCODE_SANDBOX_CPUS}"
[ -n "${GOOGLE_CLOUD_PROJECT}" ] && echo "  gcp:       project=${GOOGLE_CLOUD_PROJECT}"
[ -n "${OPENAI_BASE_URL}" ]      && echo "  openai:    ${OPENAI_BASE_URL}"
[ -n "${ANTHROPIC_API_KEY}" ]    && echo "  anthropic: (key set)"
[ -n "${LOCAL_MCP_HOST}" ]       && echo "  mcp:       local-mcp -> ${LOCAL_MCP_HOST}:8888"
echo

MCP_ARGS=()
if [ -n "${LOCAL_MCP_HOST}" ]; then
    MCP_ARGS+=(--add-host "local-mcp:${LOCAL_MCP_HOST}")
fi

exec podman run \
    --rm \
    -it \
    --annotation run.oci.handler=krun \
    --annotation "krun.ram_mib=${OPENCODE_SANDBOX_RAM}" \
    --annotation "krun.cpus=${OPENCODE_SANDBOX_CPUS}" \
    -v "${OPENCODE_SANDBOX_HOME}:/home/opencode:U,z" \
    -v "${OPENCODE_SANDBOX_ALLOWED_DIR}:${OPENCODE_SANDBOX_ALLOWED_DIR}:z" \
    ${PROVIDER_MOUNTS[@]+"${PROVIDER_MOUNTS[@]}"} \
    ${PROVIDER_ENV[@]+"${PROVIDER_ENV[@]}"} \
    ${MCP_ARGS[@]+"${MCP_ARGS[@]}"} \
    -e "TZ=${TZ}" \
    -e "TERM=xterm-256color" \
    -e "COLORTERM=truecolor" \
    -w "${CURRENT_DIR}" \
    "${OPENCODE_SANDBOX_IMAGE}" \
    "$CMD" "${PARAMS[@]}"
