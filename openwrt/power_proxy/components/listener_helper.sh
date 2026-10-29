#!/bin/sh

# =============================================================================
# Wake-on-LAN dispatch guard and bounded boot-wait helpers
# =============================================================================

# A failed bind or an `nc -w 2` timeout can make a wake listener fire again
# immediately. A single magic packet is enough to wake the host, so repeats
# within this window are suppressed instead of flooding the sleeping host.
WOL_COOLDOWN_SEC="${WOL_COOLDOWN_SEC:-30}"
WOL_COOLDOWN_FILE="${WOL_COOLDOWN_FILE:-/tmp/power_proxy_wol_cooldown}"

# How long to wait for the host/game service to come back after a magic packet.
# 90 attempts x 2s ~= 3 minutes; the magic packet is re-issued every 15
# attempts (~30s) in case the first one was lost on the wire.
WAKE_WAIT_ATTEMPTS="${WAKE_WAIT_ATTEMPTS:-90}"
WAKE_WAIT_INTERVAL="${WAKE_WAIT_INTERVAL:-2}"
WAKE_REWOL_EVERY="${WAKE_REWOL_EVERY:-15}"

# send_wol <interface> <mac>: dispatch a magic packet unless one was sent very
# recently. Returns 0 when a packet was sent, 1 when suppressed by the cooldown.
send_wol() {
    _wol_iface="$1"
    _wol_mac="$2"
    _wol_last=$(cat "$WOL_COOLDOWN_FILE" 2>/dev/null)

    case "$_wol_last" in
        ''|*[!0-9]*) _wol_last="" ;;
    esac

    if [ -n "$_wol_last" ]; then
        _wol_now=$(date +%s)
        if [ $((_wol_now - _wol_last)) -lt "$WOL_COOLDOWN_SEC" ]; then
            echo "Wake-on-LAN suppressed: a magic packet was already sent less than ${WOL_COOLDOWN_SEC}s ago."
            return 1
        fi
    fi

    echo "Dispatching Wake-on-LAN magic packet to $_wol_mac on $_wol_iface..."
    if ! etherwake -i "$_wol_iface" "$_wol_mac"; then
        log_router "Wake-on-LAN dispatch to $_wol_mac on $_wol_iface returned non-zero."
    fi
    # Record the attempt (even a failed one) so a broken interface cannot make
    # the listener hammer the host with a magic packet every iteration.
    date +%s > "$WOL_COOLDOWN_FILE" 2>/dev/null
    return 0
}

# wait_for_host_boot <interface> <mac>: bounded wait for the Proxmox host to
# answer. Returns 1 (with a syslog warning) when the host never came up, so the
# caller can abort instead of spinning forever.
wait_for_host_boot() {
    _boot_iface="$1"
    _boot_mac="$2"
    _boot_attempt=0

    while [ "$_boot_attempt" -lt "$WAKE_WAIT_ATTEMPTS" ]; do
        if is_host_alive; then
            return 0
        fi

        _boot_attempt=$((_boot_attempt + 1))
        if [ $((_boot_attempt % WAKE_REWOL_EVERY)) -eq 0 ]; then
            echo "Host still offline after $((_boot_attempt * WAKE_WAIT_INTERVAL))s. Re-issuing Wake-on-LAN..."
            send_wol "$_boot_iface" "$_boot_mac"
        fi
        sleep "$WAKE_WAIT_INTERVAL"
    done

    log_router "Host $HOST_IP did not come online after $((_boot_attempt * WAKE_WAIT_INTERVAL))s of waiting."
    return 1
}

# wait_for_game_boot <interface> <mac>: same bounded wait for the game listener.
# The host must be pingable and, for TCP ports, the real game service must
# answer before the listener declares success.
wait_for_game_boot() {
    _game_iface="$1"
    _game_mac="$2"
    _game_attempt=0

    while [ "$_game_attempt" -lt "$WAKE_WAIT_ATTEMPTS" ]; do
        if ping -c 1 -W 1 "$HOST_IP" >/dev/null 2>&1; then
            if [ "$PROTO" != "tcp" ]; then
                echo "Real host $HOST_IP is now awake and pingable. UDP service on port $PORT_NUM is active."
                return 0
            fi
            if nc -w 1 -z "$HOST_IP" "$PORT_NUM" >/dev/null 2>&1; then
                echo "Real game server on $HOST_IP:$PORT_NUM (TCP) is now ONLINE."
                return 0
            fi
        fi

        _game_attempt=$((_game_attempt + 1))
        if [ $((_game_attempt % WAKE_REWOL_EVERY)) -eq 0 ]; then
            echo "Game service on port $PORT_RAW still unreachable after $((_game_attempt * WAKE_WAIT_INTERVAL))s. Re-issuing Wake-on-LAN..."
            send_wol "$_game_iface" "$_game_mac"
        fi
        sleep "$WAKE_WAIT_INTERVAL"
    done

    log_router "Game service on port $PORT_RAW ($HOST_IP) did not come online after $((_game_attempt * WAKE_WAIT_INTERVAL))s of waiting."
    return 1
}

# Start Game Listeners in the background
start_game_listeners() {
    if [ "$ENABLE_PORT_WAKE_LISTENERS" = "0" ]; then
        echo "Port wake listeners are disabled, bypassing raw game wake listeners."
        return
    fi
    echo "Starting Game Wake-on-Demand listeners..."
    GAME_PIDS=""

    for port in $(echo "$GAME_REDIRECT_PORTS" | tr ',' ' '); do
        if [ -n "$port" ]; then
            /usr/bin/game_wake_listener.sh "$port" &
            GAME_PIDS="$GAME_PIDS $!"
        fi
    done
}

# Stop Game Listeners
stop_game_listeners() {
    echo "Stopping Game Wake-on-Demand listeners..."

    # Clean up background listeners by PID
    if [ -n "$GAME_PIDS" ]; then
        for pid in $GAME_PIDS; do
            kill "$pid" 2>/dev/null
        done
        GAME_PIDS=""
    fi

    # Also grep kill to ensure no orphaned listeners remain
    pkill -f "game_wake_listener.sh" 2>/dev/null
}

# Start Guest Listeners for any suspended guests
manage_guest_listeners() {
    [ -z "$GUEST_ORCHESTRATION_MAP" ] && return
    if [ "$ENABLE_PORT_WAKE_LISTENERS" = "0" ]; then
        return
    fi

    for entry in $(echo "$GUEST_ORCHESTRATION_MAP" | tr ',' ' '); do
        VMID=$(echo "$entry" | cut -d':' -f1)
        GUEST_IP=$(echo "$entry" | cut -d':' -f2)
        PORT_RAW=$(echo "$entry" | cut -d':' -f3)

        # Skip Wake-on-Demand listeners if no port is defined
        if [ -z "$PORT_RAW" ]; then
            continue
        fi

        if ping -c 1 -W 1 "$GUEST_IP" >/dev/null 2>&1; then
            if pgrep -f "guest_wake_listener.sh $GUEST_IP " >/dev/null 2>&1; then
                echo "Guest [$VMID] ($GUEST_IP) came online. Terminating listener..."
                pkill -f "guest_wake_listener.sh $GUEST_IP "
                ip addr del "${GUEST_IP}/32" dev "$IFACE" >/dev/null 2>&1 || true
            fi
        else
            for sub_port in $(echo "$PORT_RAW" | tr '+' ' '); do
                if ! pgrep -f "guest_wake_listener.sh $GUEST_IP $sub_port " >/dev/null 2>&1; then
                    echo "Guest [$VMID] ($GUEST_IP) is offline. Starting Wake-on-Demand listener on $sub_port..."
                    /usr/bin/guest_wake_listener.sh "$GUEST_IP" "$sub_port" "$VMID" &
                fi
            done
        fi
    done
}

# Stop all individual guest listeners
stop_guest_listeners() {
    echo "Stopping all individual guest Wake-on-Demand listeners..."
    pkill -f "guest_wake_listener.sh" 2>/dev/null

    if [ -n "$GUEST_ORCHESTRATION_MAP" ]; then
        for entry in $(echo "$GUEST_ORCHESTRATION_MAP" | tr ',' ' '); do
            GUEST_IP=$(echo "$entry" | cut -d':' -f2)
            ip addr del "${GUEST_IP}/32" dev "$IFACE" >/dev/null 2>&1 || true
        done
    fi
}

listen_game() {
    if [ "$PROTO" = "udp" ]; then
        echo "Starting UDP listener on port $PORT_NUM..."
        nc -u -l -p "$PORT_NUM" -w 2 >/dev/null 2>&1 &
    else
        echo "Starting TCP listener on port $PORT_NUM..."
        nc -l -p "$PORT_NUM" -w 2 >/dev/null 2>&1 &
    fi
    NC_PID=$!
}

listen_guest() {
    if [ "$PROTO" = "udp" ]; then
        echo "Listening on UDP ${GUEST_IP}:${PORT_NUM}..."
        nc -u -l -p "$PORT_NUM" -s "$GUEST_IP" -w 2 >/dev/null 2>&1 &
    else
        echo "Listening on TCP ${GUEST_IP}:${PORT_NUM}..."
        nc -l -p "$PORT_NUM" -s "$GUEST_IP" -w 2 >/dev/null 2>&1 &
    fi
    NC_PID=$!
}
