#!/bin/bash
set -euo pipefail

SCRIPTS_DIR="/opt/vandbox/scripts"
CONFIG_DIR="/opt/vandbox/config"
LOG_DIR="/var/log/vandbox"
AUDIT_LOG="${LOG_DIR}/audit.jsonl"

VANDBOX_MODE="${VANDBOX_MODE:-enforce}"
VANDBOX_NETWORK_ALLOWLIST="${VANDBOX_NETWORK_ALLOWLIST:-${CONFIG_DIR}/network-allowlist.conf}"
VANDBOX_BINARY_ALLOWLIST="${VANDBOX_BINARY_ALLOWLIST:-${CONFIG_DIR}/binary-allowlist.conf}"

log_event() {
    local event="$1"
    shift
    printf '{"ts":"%s","event":"%s"%s}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" \
        "${event}" \
        "$*" >> "${AUDIT_LOG}"
}

cleanup() {
    log_event "sandbox_exit" ',"mode":"'"${VANDBOX_MODE}"'"'

    if [ -n "${AUDIT_PID:-}" ] && kill -0 "${AUDIT_PID}" 2>/dev/null; then
        kill "${AUDIT_PID}" 2>/dev/null || true
        wait "${AUDIT_PID}" 2>/dev/null || true
    fi

    if [ "${VANDBOX_MODE}" = "record" ] && [ -f "${LOG_DIR}/strace.log" ]; then
        echo "Generating seccomp profile from recorded syscalls..."
        python3 /opt/vandbox/seccomp/generate-profile.py \
            --input "${LOG_DIR}/strace.log" \
            --output "${LOG_DIR}/generated-seccomp.json" \
            --summary
    fi
}

trap cleanup EXIT

for f in "${VANDBOX_NETWORK_ALLOWLIST}" "${VANDBOX_BINARY_ALLOWLIST}"; do
    if [ ! -f "$f" ]; then
        echo "ERROR: Config file not found: $f" >&2
        exit 1
    fi
done

echo "=== Vandbox Sandbox ==="
echo "Mode: ${VANDBOX_MODE}"
echo ""

chown sandbox:sandbox /workspace 2>/dev/null || true
chown sandbox:sandbox "${LOG_DIR}" 2>/dev/null || true

echo "[1/3] Configuring network allowlist..."
"${SCRIPTS_DIR}/setup-network.sh" "${VANDBOX_NETWORK_ALLOWLIST}" "${AUDIT_LOG}"

echo "[2/3] Enforcing binary allowlist..."
"${SCRIPTS_DIR}/enforce-binaries.sh" "${VANDBOX_BINARY_ALLOWLIST}" "${AUDIT_LOG}"

echo "[3/3] Starting audit logger..."
"${SCRIPTS_DIR}/audit-logger.sh" "${AUDIT_LOG}" &
AUDIT_PID=$!

log_event "sandbox_init" ',"mode":"'"${VANDBOX_MODE}"'","network_config":"'"${VANDBOX_NETWORK_ALLOWLIST}"'","binary_config":"'"${VANDBOX_BINARY_ALLOWLIST}"'"'

echo ""
echo "Sandbox ready. Dropping privileges to 'sandbox' user."
echo "==========================="
echo ""

if [ $# -eq 0 ]; then
    set -- /bin/bash
fi

if [ "${VANDBOX_MODE}" = "record" ]; then
    STRACE_LOG="${LOG_DIR}/strace.log"
    exec runuser -u sandbox -- strace -f -o "${STRACE_LOG}" -- "$@"
fi

exec runuser -u sandbox -- "$@"
