#!/bin/sh
# =============================================================================
# /node Bot Command Handler
#   /node <vm|ct> <vmid> <start|stop|restart>
# Delegates to guest_action() so it behaves identically to /ct* and /vm*
# (including the "already running" short-circuit on start).
# File: /usr/bin/telegram_components/commands/node_command.sh
# =============================================================================

node_command() {
    local chat_id="$1"
    local message_id="$2"
    local operation="$3"
    local type="$4"
    local vmid="$5"

    if [ -z "$vmid" ] || ! echo "$vmid" | grep -qE '^[0-9]+$'; then
        send_message "$chat_id" "$MSG_BOT_MAINT_ERR_NUMERIC" "" "$message_id"
        return
    fi

    local tool
    case "$type" in
        vm|qemu)             tool="qm" ;;
        ct|pct|lxc|container) tool="pct" ;;
        *)
            export arg1="$type"
            send_message "$chat_id" "$(render_msg "$MSG_BOT_NODE_ERR_INVALID_TYPE")" "" "$message_id"
            return
            ;;
    esac

    local op
    case "$operation" in
        start)   op="start" ;;
        stop)    op="stop" ;;
        restart) op="reboot" ;;
        *)
            export arg1="$operation"
            send_message "$chat_id" "$(render_msg "$MSG_BOT_NODE_ERR_INVALID_OP")" "" "$message_id"
            return
            ;;
    esac

    guest_action "$chat_id" "$message_id" "$vmid" "$tool" "$op"
}
