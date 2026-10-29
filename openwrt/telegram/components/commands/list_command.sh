#!/bin/sh
# =============================================================================
# /list Bot Command Handler
# File: /usr/bin/telegram_components/commands/list_command.sh
# =============================================================================

list_command() {
    local chat_id="$1"
    local msg_id="$2"

    if ! is_host_alive; then
        send_message "$chat_id" "$MSG_BOT_LIST_HOST_OFFLINE" "" "$msg_id"
        return
    fi

    local payload rc
    payload=$($SSH_CMD "echo '===LXC==='; pct list; echo '===VM==='; qm list" 2>/dev/null)
    rc=$?
    if [ "$rc" -ne 0 ] || [ -z "$payload" ]; then
        send_message "$chat_id" "$MSG_BOT_SSH_FAILED" "" "$msg_id"
        return
    fi

    local lxcs=$(echo "$payload" | awk '
        /===LXC===/{flag=1; next}
        /===VM===/{flag=0}
        flag && NR>2 && $1 != "VMID" {
            print "• LXC #" $1 " (" $3 "): " $2
        }
    ')
    local vms=$(echo "$payload" | awk '
        /===VM===/{flag=1; next}
        flag && NR>2 && $1 != "VMID" {
            print "• VM #" $1 " (" $2 "): " $3
        }
    ')

    [ -z "$lxcs" ] && lxcs="None configured."
    [ -z "$vms" ] && vms="None configured."

    local list_msg="*Proxmox Guest Nodes:*

*Containers:*
${lxcs}

*Virtual Machines:*
${vms}"

    send_message "$chat_id" "$list_msg" "" "$msg_id"
}
