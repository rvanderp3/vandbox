#!/bin/bash
set -euo pipefail

ALLOWLIST_FILE="$1"
AUDIT_LOG="$2"

log_event() {
    printf '{"ts":"%s","event":"%s"%s}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" \
        "$1" "$2" >> "${AUDIT_LOG}"
}

RULES_FILE=$(mktemp)

cat > "${RULES_FILE}" <<'HEADER'
table inet vandbox {
    chain input {
        type filter hook input priority 0; policy drop;
        iif "lo" accept
        ct state established,related accept
    }
    chain output {
        type filter hook output priority 0; policy drop;
        oif "lo" accept
        ct state established,related accept
HEADER

DNS_CONFIGURED=false

while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    line="$(echo "$line" | xargs 2>/dev/null)" || continue
    [ -z "$line" ] && continue

    if [ "$line" = "dns:53" ]; then
        NAMESERVER=$(awk '/^nameserver/{print $2; exit}' /etc/resolv.conf)
        if [ -n "${NAMESERVER}" ]; then
            echo "        ip daddr ${NAMESERVER} udp dport 53 accept" >> "${RULES_FILE}"
            echo "        ip daddr ${NAMESERVER} tcp dport 53 accept" >> "${RULES_FILE}"
            DNS_CONFIGURED=true
            log_event "net_allow" ',"dest":"'"${NAMESERVER}:53"'","proto":"udp+tcp","type":"dns"'
            echo "  Allow DNS -> ${NAMESERVER}:53"
        fi
        continue
    fi

    HOST="${line%%:*}"
    PORT="${line##*:}"

    if echo "$HOST" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$'; then
        echo "        ip daddr ${HOST} tcp dport ${PORT} accept" >> "${RULES_FILE}"
        log_event "net_allow" ',"dest":"'"${HOST}:${PORT}"'","proto":"tcp","type":"ip"'
        echo "  Allow -> ${HOST}:${PORT}"
    else
        RESOLVED=$(getent ahosts "$HOST" 2>/dev/null | awk '{print $1}' | sort -u) || true
        if [ -z "$RESOLVED" ]; then
            echo "  WARNING: Cannot resolve ${HOST} - skipping" >&2
            log_event "net_resolve_fail" ',"host":"'"${HOST}"'"'
            continue
        fi
        for IP in $RESOLVED; do
            if echo "$IP" | grep -q ':'; then
                echo "        ip6 daddr ${IP} tcp dport ${PORT} accept" >> "${RULES_FILE}"
            else
                echo "        ip daddr ${IP} tcp dport ${PORT} accept" >> "${RULES_FILE}"
            fi
            log_event "net_allow" ',"dest":"'"${IP}:${PORT}"'","host":"'"${HOST}"'","proto":"tcp","type":"hostname"'
            echo "  Allow -> ${HOST} (${IP}):${PORT}"
        done
    fi
done < "${ALLOWLIST_FILE}"

cat >> "${RULES_FILE}" <<'FOOTER'
        log prefix "VBOX_NET_DENY: " counter drop
    }
    chain forward {
        type filter hook forward priority 0; policy drop;
    }
}
FOOTER

nft -f "${RULES_FILE}"
rm -f "${RULES_FILE}"

chmod a-x /usr/sbin/nft 2>/dev/null || true

echo "  Network rules applied."
