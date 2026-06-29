#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

VANDBOX_IMAGE="${VANDBOX_IMAGE:-vandbox:record}"
VANDBOX_WORKSPACE="${VANDBOX_WORKSPACE:-${SCRIPT_DIR}/workspace}"
VANDBOX_AUDIT_DIR="${VANDBOX_AUDIT_DIR:-${SCRIPT_DIR}/audit-logs}"
VANDBOX_SECCOMP="${VANDBOX_SECCOMP:-${SCRIPT_DIR}/seccomp/record.json}"
VANDBOX_NETWORK_CONF="${VANDBOX_NETWORK_CONF:-${SCRIPT_DIR}/config/network-allowlist.conf}"
VANDBOX_BINARY_CONF="${VANDBOX_BINARY_CONF:-${SCRIPT_DIR}/config/binary-allowlist.conf}"

mkdir -p "${VANDBOX_WORKSPACE}" "${VANDBOX_AUDIT_DIR}"

echo "Vandbox: Launching sandbox (RECORD mode)"
echo "  Image:     ${VANDBOX_IMAGE}"
echo "  Workspace: ${VANDBOX_WORKSPACE}"
echo "  Audit log: ${VANDBOX_AUDIT_DIR}"
echo "  Seccomp:   ${VANDBOX_SECCOMP} (permissive)"
echo ""
echo "  All syscalls will be recorded via strace."
echo "  After exit, a minimal seccomp profile will be generated."
echo ""

podman run \
    --rm \
    $([ -t 0 ] && echo "-it" || echo "-i") \
    --name "vandbox-record-$(date +%s)" \
    --security-opt "seccomp=${VANDBOX_SECCOMP}" \
    --cap-add=NET_ADMIN \
    --cap-add=SYS_PTRACE \
    -v "${VANDBOX_WORKSPACE}:/workspace:rw,Z" \
    -v "${VANDBOX_AUDIT_DIR}:/var/log/vandbox:rw,Z" \
    -v "${VANDBOX_NETWORK_CONF}:/opt/vandbox/config/network-allowlist.conf:ro,Z" \
    -v "${VANDBOX_BINARY_CONF}:/opt/vandbox/config/binary-allowlist.conf:ro,Z" \
    --memory=4g \
    --cpus=4 \
    --pids-limit=512 \
    -e VANDBOX_MODE=record \
    "${VANDBOX_IMAGE}" \
    "$@"

EXIT_CODE=$?

if [ -f "${VANDBOX_AUDIT_DIR}/generated-seccomp.json" ]; then
    cp "${VANDBOX_AUDIT_DIR}/generated-seccomp.json" "${SCRIPT_DIR}/seccomp/generated.json"
    echo ""
    echo "=== Seccomp Profile Generated ==="
    echo "  Saved to: seccomp/generated.json"
    echo ""
    echo "  To use in enforce mode:"
    echo "    VANDBOX_SECCOMP=${SCRIPT_DIR}/seccomp/generated.json ./run.sh"
    echo ""
fi

exit ${EXIT_CODE}
