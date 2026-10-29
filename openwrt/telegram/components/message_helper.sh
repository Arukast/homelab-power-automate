#!/bin/sh
# =============================================================================
# OpenWrt Telegram Bot Message Helper
# Markup definitions, template expansion and message delivery.
# File: /usr/bin/telegram_components/message_helper.sh
# =============================================================================

# Helper to generate context-specific inline keyboard markup
get_markup() {
    local type="$1"
    case "$type" in
        help)
            cat <<EOF
{"inline_keyboard": [
    [{"text": "Status", "callback_data": "/status"}, {"text": "Wake", "callback_data": "/wake"}],
    [{"text": "List", "callback_data": "/list"}, {"text": "Maint", "callback_data": "/maintenance status"}]
]}
EOF
            ;;
        status_online)
            cat <<EOF
{"inline_keyboard": [
    [{"text": "List", "callback_data": "/list"}, {"text": "Sleep", "callback_data": "/sleep"}],
    [{"text": "Refresh", "callback_data": "/status"}]
]}
EOF
            ;;
        status_offline)
            cat <<EOF
{"inline_keyboard": [
    [{"text": "Wake Host", "callback_data": "/wake"}]
]}
EOF
            ;;
        list)
            cat <<EOF
{"inline_keyboard": [
    [{"text": "Status", "callback_data": "/status"}, {"text": "Maint", "callback_data": "/maintenance status"}]
]}
EOF
            ;;
        maintenance)
            cat <<EOF
{"inline_keyboard": [
    [{"text": "Status", "callback_data": "/maintenance status"}, {"text": "Main Menu", "callback_data": "/help"}]
]}
EOF
            ;;
        wake)
            cat <<EOF
{"inline_keyboard": [
    [{"text": "Main Menu", "callback_data": "/status"}]
]}
EOF
            ;;
        *)
            echo ""
            ;;
    esac
}

# Helper to expand messages with placeholders $arg1..$arg4 (and $HOST_MAC etc.)
# Delegates to render_msg() from the shared library (components/lib.sh), which
# substitutes tokens with the CURRENT shell values using pure parameter
# expansion — no eval and no sed program built from message data.
expand_msg() {
    render_msg "$1"
}

# Helper to send messages to Telegram with Markdown auto-fallback.
# Public signature: send_message <chat_id> <text> [markup] [message_id]
# When message_id is non-empty the message is edited in place.
send_message() {
    local chat_id="$1"
    local raw_text="$2"
    local markup="$3"
    local message_id="$4"

    # Expand placeholders here, inside the function, using the current environment
    local text
    text=$(expand_msg "$raw_text")

    # Collapse markup JSON to a single line (heredocs in get_markup produce newlines
    # that make the JSON awkward to pass through the API)
    local markup_inline
    markup_inline=$(printf '%s' "$markup" | tr -d '\n')

    # tg_send handles sendMessage/editMessageText, the Markdown→plain retry and
    # the curl connect/max timeouts.
    tg_send "$chat_id" "$text" "$markup_inline" "$message_id"
}
