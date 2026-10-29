#!/bin/sh
# =============================================================================
# /stop Bot Command Handler (guest stop)
#   /stop <vmid>  — stops a VM or LXC; the type is auto-detected from the VMID.
# File: /usr/bin/telegram_components/commands/stop_command.sh
# =============================================================================

stop_command() {
    guest_action "$1" "$2" "$3" auto stop
}
