#!/bin/bash
set -euo pipefail

ALLOWLIST_FILE="$1"
AUDIT_LOG="$2"

log_event() {
    printf '{"ts":"%s","event":"%s"%s}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" \
        "$1" "$2" >> "${AUDIT_LOG}"
}

declare -A ALLOWED

ALLOWED["/opt/vandbox/scripts/entrypoint.sh"]=1
ALLOWED["/opt/vandbox/scripts/setup-network.sh"]=1
ALLOWED["/opt/vandbox/scripts/enforce-binaries.sh"]=1
ALLOWED["/opt/vandbox/scripts/audit-logger.sh"]=1
ALLOWED["/opt/vandbox/seccomp/generate-profile.py"]=1
ALLOWED["/usr/sbin/runuser"]=1
ALLOWED["/usr/bin/su"]=1
ALLOWED["/usr/bin/strace"]=1
ALLOWED["/usr/bin/coreutils"]=1

while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    line="$(echo "$line" | xargs 2>/dev/null)" || continue
    [ -z "$line" ] && continue
    ALLOWED["$line"]=1
done < "${ALLOWLIST_FILE}"

# Auto-allow shebang interpreters used by allowed scripts.
for bin in "${!ALLOWED[@]}"; do
    [ -f "$bin" ] || continue
    magic=$(dd if="$bin" bs=1 count=2 2>/dev/null) || continue
    [ "$magic" = "#!" ] || continue
    interp=$(head -1 "$bin" 2>/dev/null) || continue
    interp="${interp#\#!}"
    interp="${interp# }"
    interp="${interp%% *}"
    if [ -n "$interp" ] && [ -f "$interp" ]; then
        ALLOWED["$interp"]=1
    fi
done

STRIPPED=0
KEPT=0

# Only process regular files, not symlinks.
# chmod follows symlinks by default and would damage targets outside
# the scanned directories (e.g., /usr/bin/ld.so -> ld-linux-x86-64.so.2).
# Symlinks to stripped targets are already harmless since the target
# itself has lost execute permission.
for dir in /usr/bin /usr/sbin /usr/local/bin; do
    [ -d "$dir" ] || continue

    while IFS= read -r binary; do
        REAL_PATH=$(readlink -f "$binary" 2>/dev/null) || REAL_PATH="$binary"

        if [ -n "${ALLOWED[$binary]:-}" ] || [ -n "${ALLOWED[$REAL_PATH]:-}" ]; then
            KEPT=$((KEPT + 1))
            continue
        fi

        chmod a-x "$binary" 2>/dev/null || true
        STRIPPED=$((STRIPPED + 1))
        escaped_path=$(printf '%s' "$binary" | sed 's/\\/\\\\/g; s/"/\\"/g')
        log_event "binary_stripped" ',"path":"'"$escaped_path"'"'
    done < <(find "$dir" -maxdepth 1 -type f -executable 2>/dev/null)
done

echo "  Binaries: ${KEPT} allowed, ${STRIPPED} stripped"
log_event "binary_enforce_complete" ',"allowed":'"${KEPT}"',"stripped":'"${STRIPPED}"
