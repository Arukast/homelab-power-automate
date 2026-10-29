#!/bin/sh
# =============================================================================
# OpenWrt Shell Telegram Bot Daemon for Homelab Power Control
# File: /usr/bin/telegram_bot_daemon.sh
# =============================================================================

# Load common initialization (paths, config, SSH vars)
. /usr/bin/components/common_init.sh

# Load telegram-specific components
. "$TB_COMP"/liveness_monitor.sh
. "$TB_COMP"/message_helper.sh
. "$TB_COMP"/maintenance_helper.sh
. "$TB_COMP"/polling_helper.sh
. "$TB_COMP"/process_command_helper.sh
. "$TB_COMP"/command_helper.sh

# Load command handlers
for cmd_file in "$TB_COMP"/commands/*_command.sh; do
    . "$cmd_file"
done

# Read Config
init_common_config

# Initialize SSH connection parameters
init_ssh_vars

PIDFILE="/var/run/telegram_bot_daemon.pid"
init_daemon_pid "$PIDFILE" "telegram_bot_daemon.sh"

# Check token
is_telegram_bot_token

# Start the Host Liveness Monitor: at most one instance, and tied to this
# daemon's lifetime. Without the pid guard, a procd restart left the old monitor
# orphaned while a new one started, producing duplicate ONLINE/OFFLINE messages.
LIVENESS_PIDFILE="/var/run/telegram_liveness_monitor.pid"
LIVENESS_PID=""
if [ -f "$LIVENESS_PIDFILE" ] && kill -0 "$(cat "$LIVENESS_PIDFILE" 2>/dev/null)" 2>/dev/null; then
    echo "Host Liveness Monitor already running; not starting another." >&2
else
    monitor_host_liveness &
    LIVENESS_PID=$!
    echo "$LIVENESS_PID" > "$LIVENESS_PIDFILE"
fi

cleanup_all() {
    [ -n "$LIVENESS_PID" ] && kill "$LIVENESS_PID" 2>/dev/null
    rm -f "$LIVENESS_PIDFILE" "$PIDFILE"
    exit 0
}
trap cleanup_all SIGTERM SIGINT EXIT

# Check host alliveness
is_host_alive

# Main polling loop
poll_updates
