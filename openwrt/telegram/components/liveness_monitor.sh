#!/bin/sh
# =============================================================================
# Host Liveness Monitoring Component
# File: /usr/bin/telegram_components/liveness_monitor.sh
# =============================================================================

monitor_host_liveness() {
    # Ensure only one instance of the monitor runs.
    # This function is launched in the background (monitor_host_liveness &), so
    # its body runs in a subshell where $$ is the PARENT daemon's PID — a pidfile
    # written with $$ would never represent the monitor itself. An atomic
    # mkdir-based lock is released automatically when the monitor exits.
    local LIVENESS_LOCK="/var/run/telegram_liveness_monitor.lock"
    if ! mkdir "$LIVENESS_LOCK" 2>/dev/null; then
        echo "Host Liveness Monitor already running (lock: $LIVENESS_LOCK)." >&2
        return 1
    fi
    trap 'rmdir "$LIVENESS_LOCK" 2>/dev/null' EXIT SIGTERM SIGINT

    echo "Starting Host Liveness Monitor..."
    
    # Initial state
    local current_state
    if is_host_alive; then
        current_state="online"
    else
        current_state="offline"
    fi
    
    # Persistent state + an atomic mutex, so that even if more than one monitor
    # instance is running only ONE of them emits a given transition.
    local STATE_FILE="/var/run/telegram_liveness_state"
    local NOTIFY_LOCK="/var/run/telegram_liveness_notify.lock"
    [ -f "$STATE_FILE" ] || echo "$current_state" > "$STATE_FILE" 2>/dev/null

    # Use the first authorized user as default notification target
    local notify_chat_id="${NOTIFY_CHAT_ID:-$(echo "$ALLOWED_USER_IDS" | cut -d',' -f1)}"
    
    if [ -z "$notify_chat_id" ]; then
        echo "Liveness Monitor: No notification chat ID configured. Monitoring only."
        # We can still monitor, but we can't notify
    fi

    # Track a "pending" state to debounce flappy transitions.
    # A transition is only confirmed (and notified) after 2 consecutive checks agree.
    local pending_state=""

    while true; do
        local next_state
        if is_host_alive; then
            next_state="online"
        else
            next_state="offline"
        fi

        if [ "$current_state" != "$next_state" ]; then
            # State differs from confirmed state — start or continue debounce
            if [ "$pending_state" = "$next_state" ]; then
                # Second consecutive check confirms the transition — notify now
                echo "Liveness Monitor: State transition confirmed: $current_state -> $next_state"
                
                # Claim the transition atomically: the persisted state is the
                # source of truth, so a second monitor instance sees it already
                # applied and stays quiet.
                local _claimed=0 _last=""
                if mkdir "$NOTIFY_LOCK" 2>/dev/null; then
                    _last=$(cat "$STATE_FILE" 2>/dev/null)
                    if [ "$_last" != "$next_state" ]; then
                        echo "$next_state" > "$STATE_FILE" 2>/dev/null
                        _claimed=1
                    fi
                    rmdir "$NOTIFY_LOCK" 2>/dev/null
                fi
                if [ "$_claimed" -eq 1 ] && [ -n "$notify_chat_id" ]; then
                    if [ "$next_state" = "online" ]; then
                        send_message "$notify_chat_id" "$(expand_msg "${MSG_BOT_HOST_ONLINE:-Host is now ONLINE and reachable.}")" ""
                    else
                        send_message "$notify_chat_id" "$(expand_msg "${MSG_BOT_HOST_OFFLINE:-Host is now OFFLINE or suspended.}")" ""
                    fi
                fi
                current_state="$next_state"
                pending_state=""
                # Full interval before next check after confirmed transition
                sleep 60
            else
                # First check showing a different state — record it, wait a short
                # interval and check again before committing
                echo "Liveness Monitor: Possible state change detected ($current_state -> $next_state), debouncing..."
                pending_state="$next_state"
                sleep 15
            fi
        else
            # State matches confirmed state — clear any pending debounce
            pending_state=""
            sleep 60
        fi
    done
}
