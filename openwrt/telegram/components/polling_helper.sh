#!/bin/sh
# =============================================================================
# OpenWrt Telegram Bot Long-Polling Loop
# File: /usr/bin/telegram_components/polling_helper.sh
# =============================================================================

# Persisted long-poll offset. Persisting it means that if the daemon crashes
# mid-command, the already-processed update is not replayed on the next boot
# (which could otherwise re-run a destructive command such as /hostshutdown).
OFFSET_FILE="/var/run/telegram_offset"

# Main polling loop
poll_updates() {
    # Resume from the last acknowledged update, defaulting to 0 on a cold boot.
    OFFSET=0
    if [ -f "$OFFSET_FILE" ]; then
        local saved_offset
        saved_offset=$(cat "$OFFSET_FILE" 2>/dev/null)
        if echo "$saved_offset" | grep -qE "^[0-9]+$"; then
            OFFSET="$saved_offset"
        fi
    fi

    echo "Starting Homelab Telegram Bot Daemon..."

    # Clear any active webhook so long polling functions reliably
    curl -s "https://api.telegram.org/bot${BOT_TOKEN}/deleteWebhook" >/dev/null 2>&1

    while true; do
        # Long polling with a 30s timeout
        UPDATES=$(curl -s --max-time 35 "https://api.telegram.org/bot${BOT_TOKEN}/getUpdates?offset=${OFFSET}&timeout=30")

        if [ $? -ne 0 ] || [ -z "$UPDATES" ]; then
            sleep 5
            continue
        fi

        # Check if OK
        OK=$(echo "$UPDATES" | jsonfilter -e '@.ok')
        if [ "$OK" != "true" ]; then
            echo "Telegram API Error response: $UPDATES"
            sleep 10
            continue
        fi

        # Get total count of updates
        RAW_IDS=$(echo "$UPDATES" | jsonfilter -e '@.result[*].update_id' 2>/dev/null)
        if [ -z "$RAW_IDS" ]; then
            continue
        fi
        COUNT=$(echo "$RAW_IDS" | grep -c .)
        if [ "$COUNT" -eq 0 ]; then
            continue
        fi

        i=0
        while [ $i -lt $COUNT ]; do
            UPDATE_ID=$(echo "$UPDATES" | jsonfilter -e "@.result[$i].update_id")

            # A callback's source message id must never leak into the next
            # (possibly plain-message) update.
            CALLBACK_MSG_ID=""

            # Try to parse normal message
            USER_ID=$(echo "$UPDATES" | jsonfilter -e "@.result[$i].message.from.id")
            CHAT_ID=$(echo "$UPDATES" | jsonfilter -e "@.result[$i].message.chat.id")
            CMD_TEXT=$(echo "$UPDATES" | jsonfilter -e "@.result[$i].message.text")
            CALLBACK_ID=$(echo "$UPDATES" | jsonfilter -e "@.result[$i].callback_query.id")

            # Fall back to callback query values if present
            if [ -n "$CALLBACK_ID" ]; then
                USER_ID=$(echo "$UPDATES" | jsonfilter -e "@.result[$i].callback_query.from.id")
                CHAT_ID=$(echo "$UPDATES" | jsonfilter -e "@.result[$i].callback_query.message.chat.id")
                CMD_TEXT=$(echo "$UPDATES" | jsonfilter -e "@.result[$i].callback_query.data")
                # Capture the source message id so menu handlers can update in place
                CALLBACK_MSG_ID=$(echo "$UPDATES" | jsonfilter -e "@.result[$i].callback_query.message.message_id")
            fi

            # Advance offset to acknowledge this update safely (preventing empty string shell errors)
            if [ -n "$UPDATE_ID" ] && echo "$UPDATE_ID" | grep -qE "^[0-9]+$"; then
                OFFSET=$((UPDATE_ID + 1))
            fi

            if [ -n "$CMD_TEXT" ] && [ -n "$USER_ID" ]; then
                # In groups, ignore standard conversation. Only react to slash commands.
                IS_COMMAND=0
                if echo "$CMD_TEXT" | grep -qE "^/"; then
                    IS_COMMAND=1
                fi

                if [ "$IS_COMMAND" -eq 1 ] || [ "$CHAT_ID" = "$USER_ID" ]; then
                    # Verify if user is allowed
                    AUTHORIZED=0
                    for allowed in $(echo "$ALLOWED_USER_IDS" | tr ',' ' '); do
                        if [ "$allowed" = "$USER_ID" ]; then
                            AUTHORIZED=1
                            break
                        fi
                    done

                    if [ $AUTHORIZED -eq 0 ]; then
                        # Only reply to unauthorized messages if they were actual commands (starts with '/')
                        if echo "$CMD_TEXT" | grep -qE "^/"; then
                            echo "Blocked unauthorized user ID: $USER_ID attempting command: $CMD_TEXT"
                            send_message "$CHAT_ID" "$(expand_msg "$MSG_BOT_UNAUTHORIZED")"
                        fi
                    else
                        # Execute interactive callback actions or slash commands
                        if echo "$CMD_TEXT" | grep -qE "^cmd:|^maint:|^action:"; then
                            echo "Running action: $CMD_TEXT from authorized User ID: $USER_ID"
                            process_action "$CMD_TEXT" "$CHAT_ID" "${CALLBACK_MSG_ID:-}"
                        elif echo "$CMD_TEXT" | grep -qE "^/"; then
                            echo "Running command: $CMD_TEXT from authorized User ID: $USER_ID"
                            process_command "$CMD_TEXT" "$CHAT_ID" "${CALLBACK_MSG_ID:-}"
                        elif [ "$CHAT_ID" = "$USER_ID" ]; then
                            # In private chat, if authorized user sends plain text (e.g. 'status', 'help', 'hi'), show command menu or execute match
                            echo "Received non-slash message '$CMD_TEXT' from authorized User ID: $USER_ID. Replying with command menu."
                            case "$(echo "$CMD_TEXT" | tr 'A-Z' 'a-z')" in
                                status) process_command "/status" "$CHAT_ID" ;;
                                list|vms|lxcs) process_command "/list" "$CHAT_ID" ;;
                                wake|on) process_command "/wake" "$CHAT_ID" ;;
                                sleep|off) process_command "/sleep" "$CHAT_ID" ;;
                                *) process_command "/help" "$CHAT_ID" ;;
                            esac
                        fi
                    fi
                fi
            fi

            # Acknowledge callback query if it was one
            if [ -n "$CALLBACK_ID" ]; then
                curl -s --max-time 5 -X POST "https://api.telegram.org/bot${BOT_TOKEN}/answerCallbackQuery" \
                    --data-urlencode "callback_query_id=${CALLBACK_ID}" >/dev/null &
            fi

            i=$((i + 1))
        done

        # Persist the offset only after the whole batch has been handled so that
        # a crash mid-batch replays at most the unacknowledged updates.
        echo "$OFFSET" > "$OFFSET_FILE"
    done
}
