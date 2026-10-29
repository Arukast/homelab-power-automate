#!/bin/sh
# =============================================================================
# /wake Bot Command Handler
# File: /usr/bin/telegram_components/commands/wake_command.sh
# =============================================================================

wake_command() {
    local chat_id="$1"
    local message_id="$2"

    # If the host is already reachable, do not fire a (pointless) magic packet —
    # just tell the user it is already awake.
    if is_host_alive; then
        send_message "$chat_id" "$(expand_msg "$MSG_BOT_WOL_ALREADY_AWAKE")" "" "$message_id"
        return
    fi

    send_message "$chat_id" "$(expand_msg "$MSG_BOT_WOL_SENT")" "" "$message_id"
    etherwake -i "${LAN_INTERFACE:-br-lan}" "$HOST_MAC"
    send_message "$chat_id" "$MSG_BOT_WOL_DISPATCHED" "" "$message_id"
}
