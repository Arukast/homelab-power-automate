#!/bin/sh
# =============================================================================
# OpenWrt Game Wake-on-Demand Listener
# File: /usr/bin/game_wake_listener.sh
# Usage: /usr/bin/game_wake_listener.sh <port>
# =============================================================================

# Load common initialization (paths, config, SSH vars)
. /usr/bin/components/common_init.sh

# Load power_proxy-specific components
source_required "$PP_COMP/cleanup_helper.sh"
source_required "$PP_COMP/network_helper.sh"
source_required "$PP_COMP/listener_helper.sh"

# Read Config
init_common_config

PORT_RAW="$1"

check_port

# Parse port and protocol (e.g. 19132/udp -> PORT_NUM=19132, PROTO=udp)
parse_port

trap cleanup_game SIGTERM SIGINT

# Listen on game port in background
# nc will block until a player attempts a connection.
# We set a 2-second timeout (-w 2) to ensure the listener exits quickly after
# the player hits the port, allowing the script to wake the host and monitor its boot.
listen_game

# Wait for netcat to intercept a connection
wait "$NC_PID"

# Player connection detected!
echo "Player connection detected on port $PORT_RAW. Initiating host wake sequence..."

# 1. Dispatch Wake-on-LAN (cooldown-guarded so a spurious/duplicate hit on the
#    port cannot flood the sleeping host with magic packets)
send_wol "${LAN_INTERFACE:-br-lan}" "$HOST_MAC"

# 2. Dispatch notifications
MSG=$(render_msg "$MSG_WAKE_GAME_PLAYER")
/usr/bin/homelab_notify.sh "$MSG" &

# 3. Wait for the real host service to boot up (bounded to ~3 minutes, with the
#    magic packet re-issued every ~30s). The listener exits non-zero if the
#    service never answers, so the parent daemon can retry it later.
if ! wait_for_game_boot "${LAN_INTERFACE:-br-lan}" "$HOST_MAC"; then
    log_router "Aborting game wake listener for port $PORT_RAW: host/service never came online."
    exit 1
fi

# The real server is now online! We exit.
# The parent power_proxy_daemon will remove NAT rules and clean up this listener process.
exit 0
