#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

VANDBOX_IMAGE="${VANDBOX_IMAGE:-vandbox:opencode}"
VANDBOX_WORKSPACE="${VANDBOX_WORKSPACE:-${SCRIPT_DIR}/workspace}"
VANDBOX_AUDIT_DIR="${VANDBOX_AUDIT_DIR:-${SCRIPT_DIR}/audit-logs}"
VANDBOX_SECCOMP="${VANDBOX_SECCOMP:-${SCRIPT_DIR}/seccomp/default.json}"
VANDBOX_NETWORK_CONF="${VANDBOX_NETWORK_CONF:-${SCRIPT_DIR}/config/opencode-network-allowlist.conf}"
VANDBOX_BINARY_CONF="${VANDBOX_BINARY_CONF:-${SCRIPT_DIR}/config/opencode-binary-allowlist.conf}"
VANDBOX_MEMORY="${VANDBOX_MEMORY:-4g}"
VANDBOX_CPUS="${VANDBOX_CPUS:-4}"
VANDBOX_PIDS="${VANDBOX_PIDS:-512}"

GOOGLE_CLOUD_PROJECT="${GOOGLE_CLOUD_PROJECT:-}"
VERTEX_LOCATION="${VERTEX_LOCATION:-global}"
GCLOUD_ADC_FILE="${GCLOUD_ADC_FILE:-${HOME}/.config/gcloud/application_default_credentials.json}"

mkdir -p "${VANDBOX_WORKSPACE}" "${VANDBOX_AUDIT_DIR}"

if [ -z "${GOOGLE_CLOUD_PROJECT}" ]; then
    echo "ERROR: GOOGLE_CLOUD_PROJECT not set" >&2
    echo "" >&2
    echo "Set your GCP project ID:" >&2
    echo "  export GOOGLE_CLOUD_PROJECT=your-project-id" >&2
    echo "" >&2
    echo "And ensure you have authenticated:" >&2
    echo "  gcloud auth application-default login" >&2
    exit 1
fi

if [ ! -f "${GCLOUD_ADC_FILE}" ]; then
    echo "ERROR: ADC credentials not found at ${GCLOUD_ADC_FILE}" >&2
    echo "" >&2
    echo "Run: gcloud auth application-default login" >&2
    exit 1
fi

echo "Vandbox: Launching OpenCode sandbox"
echo "  Image:     ${VANDBOX_IMAGE}"
echo "  Workspace: ${VANDBOX_WORKSPACE}"
echo "  Audit log: ${VANDBOX_AUDIT_DIR}"
echo "  GCP:       project=${GOOGLE_CLOUD_PROJECT} location=${VERTEX_LOCATION}"
echo "  Limits:    memory=${VANDBOX_MEMORY} cpus=${VANDBOX_CPUS} pids=${VANDBOX_PIDS}"
echo ""

OPENCODE_MOUNTS=()

OPENCODE_CONFIG="${OPENCODE_CONFIG:-${HOME}/.opencode/opencode.json}"
if [ -f "${OPENCODE_CONFIG}" ]; then
    OPENCODE_MOUNTS+=(-v "${OPENCODE_CONFIG}:/home/sandbox/.opencode/opencode.json:ro,Z")
    echo "  Config:    ${OPENCODE_CONFIG}"
fi

exec podman run \
    --rm \
    -it \
    --name "vandbox-opencode-$(date +%s)" \
    --security-opt "seccomp=${VANDBOX_SECCOMP}" \
    --cap-add=NET_ADMIN \
    -v "${VANDBOX_WORKSPACE}:/workspace:noexec,rw,Z" \
    -v "${VANDBOX_AUDIT_DIR}:/var/log/vandbox:rw,Z" \
    -v "${VANDBOX_NETWORK_CONF}:/opt/vandbox/config/network-allowlist.conf:ro,Z" \
    -v "${VANDBOX_BINARY_CONF}:/opt/vandbox/config/binary-allowlist.conf:ro,Z" \
    -v "${GCLOUD_ADC_FILE}:/mnt/gcloud-adc/application_default_credentials.json:ro,Z" \
    "${OPENCODE_MOUNTS[@]}" \
    --memory="${VANDBOX_MEMORY}" \
    --cpus="${VANDBOX_CPUS}" \
    --pids-limit="${VANDBOX_PIDS}" \
    -e VANDBOX_MODE=enforce \
    -e GOOGLE_CLOUD_PROJECT="${GOOGLE_CLOUD_PROJECT}" \
    -e VERTEX_LOCATION="${VERTEX_LOCATION}" \
    "${VANDBOX_IMAGE}" \
    "$@"
