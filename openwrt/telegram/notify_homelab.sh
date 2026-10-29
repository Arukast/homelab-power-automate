#!/bin/sh
# =============================================================================
# OpenWrt Centralized Notification Dispatcher for Homelab Power Control
# File: /usr/bin/homelab_notify.sh
# =============================================================================

# Router-side configuration (the installed path). /etc/homelab_power.conf is the
# Proxmox-side file and does not exist on the router, so reading it here left
# BOT_TOKEN/DISCORD_WEBHOOK_URL empty and silently disabled all notifications.
CONF="/etc/power_homelab.conf"
if [ -f "$CONF" ]; then
    . "$CONF"
fi

MSG="$1"
if [ -z "$MSG" ]; then
    # Read from stdin if no argument provided
    MSG=$(cat)
fi

if [ -z "$MSG" ]; then
    exit 0
fi

# Telegram dispatch
if [ -n "$BOT_TOKEN" ] && [ "$BOT_TOKEN" != "YOUR_TELEGRAM_BOT_TOKEN" ]; then
    target_chats="${NOTIFY_CHAT_ID}"
    [ -z "$target_chats" ] && target_chats=$(echo "$ALLOWED_USER_IDS" | cut -d',' -f1)
    
    for chat in $(echo "$target_chats" | tr ',' ' '); do
        # If notifications are disabled, only notify IDs in ALLOWED_USER_IDS (admin private chats)
        if [ "$DISABLE_NOTIFICATIONS" = "1" ]; then
            is_allowed=0
            for allowed in $(echo "$ALLOWED_USER_IDS" | tr ',' ' '); do
                if [ "$chat" = "$allowed" ]; then
                    is_allowed=1
                    break
                fi
            done
            if [ "$is_allowed" -eq 0 ]; then
                continue
            fi
        fi
        
        (
            resp=$(curl -s --connect-timeout 3 --max-time 10 -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
                --data-urlencode "chat_id=${chat}" \
                --data-urlencode "text=${MSG}" \
                --data-urlencode "parse_mode=Markdown")
            # If Markdown parsing fails (e.g. unescaped entities/error 400), retry without parse_mode
            if ! echo "$resp" | grep -q '"ok":true'; then
                curl -s --connect-timeout 3 --max-time 10 -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
                    --data-urlencode "chat_id=${chat}" \
                    --data-urlencode "text=${MSG}" >/dev/null
            fi
        ) &
    done
fi

# Discord Webhook dispatch
if [ "$DISABLE_NOTIFICATIONS" != "1" ] && [ -n "$DISCORD_WEBHOOK_URL" ]; then
    color=3899126 # Default Cyber Blue
    if echo "$MSG" | grep -iqE "awake|online|restored|success"; then
        color=1095905 # Green
    elif echo "$MSG" | grep -iqE "sleep|S3|offline|down|shutdown|suspended|stopped"; then
        color=15680580 # Red
    elif echo "$MSG" | grep -iqE "reboot|rebooting"; then
        color=9133302 # Purple/Indigo
    fi
    
    clean_msg=$(printf '%s' "$MSG" | awk 'BEGIN {ORS="";} {
        gsub(/\\/, "\\\\");
        gsub(/"/, "\\\"");
        gsub(/\r/, "");
        gsub(/\t/, "\\t");
        if (NR > 1) printf "\\n";
        printf "%s", $0;
    }')
    payload="{\"embeds\":[{\"title\":\"Power Monitor Notification\",\"description\":\"${clean_msg}\",\"color\":${color},\"footer\":{\"text\":\"Arukast Homelab Portal\"}}]}"
    
    for url in $(echo "$DISCORD_WEBHOOK_URL" | tr ',' ' '); do
        if [ -n "$url" ]; then
            curl -s --connect-timeout 3 --max-time 10 -H "Content-Type: application/json" -X POST -d "$payload" "$url" >/dev/null &
        fi
    done
fi

# Wait briefly for background curl jobs to start/finish
wait
exit 0
