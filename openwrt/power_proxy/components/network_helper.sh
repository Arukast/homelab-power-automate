#!/bin/sh

bind_ip() {
    echo "Binding IP alias $GUEST_IP/32 to $IFACE..."
    ip addr add "${GUEST_IP}/32" dev "$IFACE" >/dev/null 2>&1 || true
}

# Apply Static ARP to prevent IP drops while sleeping
apply_static_arp() {
    echo "Applying permanent static ARP: $HOST_IP -> $HOST_MAC on $IFACE..."
    ip neigh replace "$HOST_IP" lladdr "$HOST_MAC" dev "$IFACE" nud permanent
}

check_port() {
    if [ -z "$PORT_RAW" ]; then
        echo "Usage: $0 <port>[/udp|/tcp]" >&2
        exit 1
    fi
}

parse_port() {
    PORT_NUM="${PORT_RAW%/*}"
    PROTO=""
    if [ "$PORT_NUM" != "$PORT_RAW" ]; then
        PROTO="${PORT_RAW#*/}"
    fi
    [ -z "$PROTO" ] && PROTO="tcp"
}
