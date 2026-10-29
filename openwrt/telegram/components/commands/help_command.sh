#!/bin/sh
# =============================================================================
# /help Bot Command Handler
# File: /usr/bin/telegram_components/commands/help_command.sh
# =============================================================================

help_command() {
    local chat_id="$1"
    local msg_id="$2"
    local markup=$(get_markup "help")
    send_message "$chat_id" "$MSG_BOT_HELP" "$markup" "$msg_id"
}