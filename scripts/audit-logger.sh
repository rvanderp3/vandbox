#!/bin/bash
set -uo pipefail

AUDIT_LOG="$1"
STATE_DIR="/var/log/vandbox/.audit-state"
mkdir -p "${STATE_DIR}"

KNOWN_PIDS="${STATE_DIR}/known_pids"
KNOWN_CONNS="${STATE_DIR}/known_conns"
FILE_MARKER="${STATE_DIR}/file_marker"

touch "${KNOWN_PIDS}" "${KNOWN_CONNS}" "${FILE_MARKER}"

log_event() {
    printf '{"ts":"%s","event":"%s"%s}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" \
        "$1" "$2" >> "${AUDIT_LOG}"
}

hex_to_ip() {
    local hex="$1"
    if [ ${#hex} -eq 8 ]; then
        printf "%d.%d.%d.%d" \
            "0x${hex:6:2}" "0x${hex:4:2}" "0x${hex:2:2}" "0x${hex:0:2}"
    else
        echo "${hex}"
    fi
}

hex_to_port() {
    printf "%d" "0x$1"
}

poll_processes() {
    local current_pids=$(mktemp)

    for proc_dir in /proc/[0-9]*; do
        [ -d "$proc_dir" ] || continue
        local pid="${proc_dir##*/}"
        local cmdline_file="${proc_dir}/cmdline"
        [ -f "$cmdline_file" ] || continue

        local cmdline
        cmdline=$(tr '\0' ' ' < "$cmdline_file" 2>/dev/null | head -c 512) || continue
        [ -z "$cmdline" ] && continue

        echo "${pid}" >> "${current_pids}"

        if ! grep -qx "${pid}" "${KNOWN_PIDS}" 2>/dev/null; then
            local user
            user=$(stat -c '%U' "$proc_dir" 2>/dev/null) || user="unknown"
            log_event "process_start" ',"pid":'"${pid}"',"cmdline":"'"$(echo "$cmdline" | sed 's/"/\\"/g' | head -c 256)"'","user":"'"${user}"'"'
        fi
    done

    while IFS= read -r old_pid; do
        [ -z "$old_pid" ] && continue
        if ! grep -qx "$old_pid" "${current_pids}" 2>/dev/null; then
            log_event "process_exit" ',"pid":'"${old_pid}"
        fi
    done < "${KNOWN_PIDS}"

    mv "${current_pids}" "${KNOWN_PIDS}"
}

poll_network() {
    local current_conns=$(mktemp)

    for tcp_file in /proc/net/tcp /proc/net/tcp6; do
        [ -f "$tcp_file" ] || continue
        tail -n +2 "$tcp_file" 2>/dev/null | while IFS=' :' read -r _ local_addr local_port remote_addr remote_port state _rest; do
            [ "$state" = "01" ] || [ "$state" = "02" ] || continue  # ESTABLISHED or SYN_SENT

            local src_ip src_port dst_ip dst_port
            src_ip=$(hex_to_ip "$local_addr")
            src_port=$(hex_to_port "$local_port")
            dst_ip=$(hex_to_ip "$remote_addr")
            dst_port=$(hex_to_port "$remote_port")

            local conn_key="${src_ip}:${src_port}-${dst_ip}:${dst_port}"
            echo "${conn_key}" >> "${current_conns}"

            if ! grep -qxF "$conn_key" "${KNOWN_CONNS}" 2>/dev/null; then
                log_event "net_connect" ',"src":"'"${src_ip}:${src_port}"'","dst":"'"${dst_ip}:${dst_port}"'"'
            fi
        done
    done

    sort -u "${current_conns}" > "${KNOWN_CONNS}" 2>/dev/null
    rm -f "${current_conns}"
}

poll_file_writes() {
    find /workspace -newer "${FILE_MARKER}" -type f 2>/dev/null | while IFS= read -r filepath; do
        local size
        size=$(stat -c '%s' "$filepath" 2>/dev/null) || size=0
        log_event "file_write" ',"path":"'"${filepath}"'","size":'"${size}"
    done
    touch "${FILE_MARKER}"
}

poll_net_denials() {
    dmesg 2>/dev/null | grep "VBOX_NET_DENY:" | while IFS= read -r line; do
        local src dst
        src=$(echo "$line" | grep -oP 'SRC=\K\S+') || src="unknown"
        dst=$(echo "$line" | grep -oP 'DST=\K\S+') || dst="unknown"
        local dpt
        dpt=$(echo "$line" | grep -oP 'DPT=\K\S+') || dpt="unknown"

        local deny_key="${src}-${dst}:${dpt}"
        if ! grep -qxF "$deny_key" "${STATE_DIR}/known_denials" 2>/dev/null; then
            echo "$deny_key" >> "${STATE_DIR}/known_denials"
            log_event "net_deny" ',"src":"'"${src}"'","dst":"'"${dst}:${dpt}"'"'
        fi
    done
}

CYCLE=0
while true; do
    poll_processes

    if [ $((CYCLE % 2)) -eq 0 ]; then
        poll_network
        poll_net_denials
    fi

    if [ $((CYCLE % 3)) -eq 0 ]; then
        poll_file_writes
    fi

    CYCLE=$(( (CYCLE + 1) % 6 ))
    sleep 1
done
