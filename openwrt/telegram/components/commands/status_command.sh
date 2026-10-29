#!/bin/sh
# =============================================================================
# /status Bot Command Handler
# File: /usr/bin/telegram_components/commands/status_command.sh
# =============================================================================

status_command() {
    local chat_id="$1"
    local msg_id="$2"

    # Initial query message
    send_message "$chat_id" "$MSG_BOT_QUERY_STATUS"

    if ! is_host_alive; then
        local markup=$(get_markup "status_offline")
        send_message "$chat_id" "$(expand_msg "$MSG_BOT_HOST_SLEEPING")" "$markup" "$msg_id"
        return
    fi

    # Host is online, gather all metrics in a single SSH connection payload!
    local metrics_payload rc
    metrics_payload=$($SSH_CMD "echo '===METRICS==='; uptime; echo '===RAM==='; free -h; echo '===LXC==='; pct list; echo '===VM==='; qm list" 2>/dev/null)
    rc=$?
    if [ "$rc" -ne 0 ] || [ -z "$metrics_payload" ]; then
        send_message "$chat_id" "$MSG_BOT_SSH_FAILED" "" "$msg_id"
        return
    fi

    local load_avg=$(echo "$metrics_payload" | awk '/===METRICS===/{getline; print}' | awk -F'load average:' '{print $2}' | sed 's/^[[:space:]]*//')
    local ram_info=$(echo "$metrics_payload" | awk '/===RAM===/{getline; getline; print $3 " / " $2}')

    # Nodes summary
    local lxc_count=$(echo "$metrics_payload" | awk '/===LXC===/{flag=1; next} /===VM===/{flag=0} flag' | awk 'NR>1' | wc -l)
    local lxc_running=$(echo "$metrics_payload" | awk '/===LXC===/{flag=1; next} /===VM===/{flag=0} flag' | awk 'NR>1 && $2=="running"' | wc -l)
    local vm_count=$(echo "$metrics_payload" | awk '/===VM===/{flag=1; next} flag' | awk 'NR>1' | wc -l)
    local vm_running=$(echo "$metrics_payload" | awk '/===VM===/{flag=1; next} flag' | awk 'NR>1 && $3=="running"' | wc -l)

    local status_msg="*Host Status:* ONLINE
*Load Average:* ${load_avg}
*RAM Usage:* ${ram_info}

*Guest Nodes:*
• LXC Containers: ${lxc_running}/${lxc_count} running
• QEMU VMs: ${vm_running}/${vm_count} running"

    local markup=$(get_markup "status_online")
    send_message "$chat_id" "$status_msg" "$markup" "$msg_id"
}
