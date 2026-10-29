#!/bin/sh
# =============================================================================
# /maintenance Bot Command Handler
# State helpers live in maintenance_helper.sh (sourced by the daemon).
# File: /usr/bin/telegram_components/commands/maintenance_command.sh
# =============================================================================

# Usage strings kept here so they stay close to the command logic
_MAINT_USAGE_SYSTEM="Usage: /maintenance system on <reason>  |  /maintenance system off"
_MAINT_USAGE_SERVICE="Usage: /maintenance service <vmid> on <reason>  |  /maintenance service <vmid> off"

# ---------------------------------------------------------------------------
# _maint_usage
# Full help text for the /maintenance command.
# ---------------------------------------------------------------------------
_maint_usage() {
    printf '%s' "[Maintenance] Blocks automated and manual power actions so guests stay up.

Usage:
• /maintenance status — show the current maintenance state
• /maintenance system on <reason> — block ALL power actions host-wide
• /maintenance system off — allow power actions again
• /maintenance service <vmid> on <reason> — block actions for one guest
• /maintenance service <vmid> off — unblock that guest
• /maintenance off — clear ALL maintenance flags at once

Examples:
/maintenance system on swapping RAM
/maintenance service 101 on disk replacement
/maintenance off"
}

# ---------------------------------------------------------------------------
# _maint_reply <chat_id> <message_id> <text>
# Thin wrapper: reply to the current interaction and return 0.
# ---------------------------------------------------------------------------
_maint_reply() {
    send_message "$1" "$3" "" "$2"
}

# ---------------------------------------------------------------------------
# _maint_system_cmd <chat_id> <message_id> <on_or_off> [reason]
# ---------------------------------------------------------------------------
_maint_system_cmd() {
    local chat_id="$1"
    local message_id="$2"
    local op="$3"
    local reason="$4"

    local out
    if [ "$op" = "off" ]; then
        out=$(maintenance_set_system off)
    else
        if [ -z "$reason" ]; then
            _maint_reply "$chat_id" "$message_id" "$_MAINT_USAGE_SYSTEM"
            return
        fi
        out=$(maintenance_set_system on "$reason")
    fi

    _maint_reply "$chat_id" "$message_id" "$out"
}

# ---------------------------------------------------------------------------
# _maint_service_cmd <chat_id> <message_id> <vmid> <on_or_off> [reason]
# ---------------------------------------------------------------------------
_maint_service_cmd() {
    local chat_id="$1"
    local message_id="$2"
    local vmid="$3"
    local op="$4"
    local reason="$5"

    if ! echo "$vmid" | grep -qE '^[0-9]+$'; then
        _maint_reply "$chat_id" "$message_id" "VMID must be a number."
        return
    fi

    local out
    if [ "$op" = "off" ]; then
        out=$(maintenance_set_service "$vmid" off)
    else
        if [ -z "$reason" ]; then
            _maint_reply "$chat_id" "$message_id" "$_MAINT_USAGE_SERVICE"
            return
        fi
        out=$(maintenance_set_service "$vmid" on "$reason")
    fi

    _maint_reply "$chat_id" "$message_id" "$out"
}

# ---------------------------------------------------------------------------
# maintenance_command <chat_id> <message_id> [sub_cmd] [arg...]
#
# Sub-commands:
#   status                        — show current maintenance state
#   system <on|off> [reason]      — toggle system-wide maintenance
#   service <vmid> <on|off> [r]   — toggle per-service maintenance
#   off                           — clear ALL maintenance flags at once
# ---------------------------------------------------------------------------
maintenance_command() {
    local chat_id="$1"
    local message_id="$2"
    local sub_cmd="$3"
    local rest="$4"

    # No sub-command → show the usage menu
    if [ -z "$sub_cmd" ]; then
        _maint_reply "$chat_id" "$message_id" "$(_maint_usage)"
        return
    fi

    # Split the remainder into fixed tokens plus a trailing reason that keeps its
    # spaces. after1 = rest without its first token; after2 = without its first
    # two tokens (e.g. rest="101 on replacing disk" → a1=101 a2=on
    # after2="replacing disk").
    local a1 a2 after1 after2
    a1=$(printf '%s' "$rest" | awk '{print $1}')
    a2=$(printf '%s' "$rest" | awk '{print $2}')
    after1=$(printf '%s' "$rest" | awk '{ $1=""; sub(/^[[:space:]]+/, ""); print }')
    after2=$(printf '%s' "$rest" | awk '{ $1=""; $2=""; sub(/^[[:space:]]+/, ""); print }')

    case "$sub_cmd" in
        help|"-h"|"--help"|"?")
            _maint_reply "$chat_id" "$message_id" "$(_maint_usage)"
            ;;

        status)
            _maint_reply "$chat_id" "$message_id" "$(maintenance_status)"
            ;;

        system)
            # /maintenance system on <reason...>   |   /maintenance system off
            if [ -z "$a1" ]; then
                _maint_reply "$chat_id" "$message_id" "$_MAINT_USAGE_SYSTEM"
                return
            fi
            _maint_system_cmd "$chat_id" "$message_id" "$a1" "$after1"
            ;;

        service)
            # /maintenance service <vmid> on <reason...>  |  ... <vmid> off
            if [ -z "$a1" ] || [ -z "$a2" ]; then
                _maint_reply "$chat_id" "$message_id" "$_MAINT_USAGE_SERVICE"
                return
            fi
            _maint_service_cmd "$chat_id" "$message_id" "$a1" "$a2" "$after2"
            ;;

        off)
            # Clear all maintenance flags in one shot
            _maint_reply "$chat_id" "$message_id" "$(maintenance_clear_all)"
            ;;

        *)
            _maint_reply "$chat_id" "$message_id" \
                "Unknown sub-command \`$sub_cmd\`. Send /maintenance for usage."
            ;;
    esac
}
