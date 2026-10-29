#!/bin/sh
# =============================================================================
# /wake Bot Command Handler
# File: /usr/bin/telegram_components/commands/wake_command.sh
# =============================================================================

wake_command() {
    send_message "$chat_id" "$(expand_msg "$MSG_BOT_WOL_SENT")"
    etherwake -i "${LAN_INTERFACE:-br-lan}" "$HOST_MAC"
    send_message "$chat_id" "$MSG_BOT_WOL_DISPATCHED" "$(get_markup "wake")"
}
