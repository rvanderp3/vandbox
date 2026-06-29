#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

VANDBOX_IMAGE="${VANDBOX_IMAGE:-vandbox:latest}"
VANDBOX_WORKSPACE="${VANDBOX_WORKSPACE:-${SCRIPT_DIR}/workspace}"
VANDBOX_AUDIT_DIR="${VANDBOX_AUDIT_DIR:-${SCRIPT_DIR}/audit-logs}"
VANDBOX_SECCOMP="${VANDBOX_SECCOMP:-${SCRIPT_DIR}/seccomp/default.json}"
VANDBOX_NETWORK_CONF="${VANDBOX_NETWORK_CONF:-${SCRIPT_DIR}/config/network-allowlist.conf}"
VANDBOX_BINARY_CONF="${VANDBOX_BINARY_CONF:-${SCRIPT_DIR}/config/binary-allowlist.conf}"
VANDBOX_MEMORY="${VANDBOX_MEMORY:-2g}"
VANDBOX_CPUS="${VANDBOX_CPUS:-2}"
VANDBOX_PIDS="${VANDBOX_PIDS:-256}"

mkdir -p "${VANDBOX_WORKSPACE}" "${VANDBOX_AUDIT_DIR}"

echo "Vandbox: Launching sandbox (enforce mode)"
echo "  Image:     ${VANDBOX_IMAGE}"
echo "  Workspace: ${VANDBOX_WORKSPACE}"
echo "  Audit log: ${VANDBOX_AUDIT_DIR}"
echo "  Seccomp:   ${VANDBOX_SECCOMP}"
echo "  Limits:    memory=${VANDBOX_MEMORY} cpus=${VANDBOX_CPUS} pids=${VANDBOX_PIDS}"
echo ""

exec podman run \
    --rm \
    $([ -t 0 ] && echo "-it" || echo "-i") \
    --name "vandbox-$(date +%s)" \
    --security-opt "seccomp=${VANDBOX_SECCOMP}" \
    --cap-add=NET_ADMIN \
    -v "${VANDBOX_WORKSPACE}:/workspace:noexec,rw,Z" \
    -v "${VANDBOX_AUDIT_DIR}:/var/log/vandbox:rw,Z" \
    -v "${VANDBOX_NETWORK_CONF}:/opt/vandbox/config/network-allowlist.conf:ro,Z" \
    -v "${VANDBOX_BINARY_CONF}:/opt/vandbox/config/binary-allowlist.conf:ro,Z" \
    --memory="${VANDBOX_MEMORY}" \
    --cpus="${VANDBOX_CPUS}" \
    --pids-limit="${VANDBOX_PIDS}" \
    -e VANDBOX_MODE=enforce \
    "${VANDBOX_IMAGE}" \
    "$@"
