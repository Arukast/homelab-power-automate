#!/bin/sh

is_pid_running() {
    local PIDFILE=$1
    local MSG=$2
    if [ -f "$PIDFILE" ]; then
        PID=$(cat "$PIDFILE" 2>/dev/null)
        if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
            echo "ERROR: $MSG is already running with PID $PID." >&2
            exit 1
        fi
    fi
    echo "$$" > "$PIDFILE"
}

# Multi-stage Host Liveness Probe: ICMP -> bounded web/TCP probe -> bounded SSH.
#
# Ordered cheap-first and EVERY stage is time-bounded. With the permanent static
# ARP entry, a sleeping host blackholes SYN packets, so an unbounded SSH connect
# hangs for the kernel TCP timeout (~2 min) on every probe; the SSH stage is
# therefore only attempted when `timeout` is available, and the bounded curl
# stage (which is present on every install) runs first.
is_host_alive() {
    if ping -c 1 -W 1 "$HOST_IP" >/dev/null 2>&1; then
        return 0
    fi

    if command -v curl >/dev/null 2>&1; then
        if curl -k -s --connect-timeout 1 "https://${HOST_IP}:8006" >/dev/null 2>&1 || \
           curl -s --connect-timeout 1 "http://${HOST_IP}:80" >/dev/null 2>&1; then
            return 0
        fi
    fi

    # Only when we can bound it; never an unbounded connect.
    if command -v timeout >/dev/null 2>&1; then
        if timeout 6 $SSH_CMD "echo OK" >/dev/null 2>&1; then
            return 0
        fi
    fi

    return 1
}

# Check token
is_telegram_bot_token() {
    if [ -z "$BOT_TOKEN" ] || [ "$BOT_TOKEN" = "YOUR_TELEGRAM_BOT_TOKEN" ]; then
        echo "ERROR: BOT_TOKEN is not configured in /etc/power_homelab.conf" >&2
        exit 1
    fi
}
