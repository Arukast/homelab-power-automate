#!/bin/sh
# =============================================================================
# OpenWrt Telegram Bot Message Helper
# Template expansion and message delivery.
# File: /usr/bin/telegram_components/message_helper.sh
# =============================================================================

# Helper to expand messages with placeholders $arg1..$arg4 (and $HOST_MAC etc.)
# Delegates to render_msg() from the shared library (components/lib.sh), which
# substitutes tokens with the CURRENT shell values using pure parameter
# expansion — no eval and no sed program built from message data.
expand_msg() {
    render_msg "$1"
}

# Helper to send messages to Telegram.
# Public signature: send_message <chat_id> <text> [markup] [message_id]
# When message_id is non-empty the message is edited in place.
# NOTE: inline keyboards are no longer used — the third (markup) argument is
# accepted only for call-site compatibility and is ignored.
send_message() {
    local chat_id="$1"
    local raw_text="$2"
    local message_id="$4"

    # Expand placeholders here, inside the function, using the current environment
    local text
    text=$(expand_msg "$raw_text")

    tg_send "$chat_id" "$text" "" "$message_id"
}
