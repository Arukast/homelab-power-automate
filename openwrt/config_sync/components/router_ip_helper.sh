#!/bin/sh

get_router_ip() {
    ROUTER_IP=$(ip route get "$HOST_IP" 2>/dev/null | grep -oE "src [0-9.]+" | awk '{print $2}')
    if [ -z "$ROUTER_IP" ]; then
        # Fallback if route fails
        ROUTER_IP=$(ip addr show dev "${LAN_INTERFACE:-br-lan}" 2>/dev/null | grep -oE 'inet [0-9.]+' | awk '{print $2}')
    fi

    if [ -z "$ROUTER_IP" ]; then
        echo "Error: Could not determine router local IP." >&2
        exit 1
    fi
    echo "Determined Router IP facing Proxmox: $ROUTER_IP"
}
