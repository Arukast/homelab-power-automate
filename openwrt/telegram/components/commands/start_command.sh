#!/bin/sh
# =============================================================================
# /start Bot Command Handler (guest start)
#   /start <vmid>  — starts a VM or LXC; the type is auto-detected from the VMID.
# A bare /start (no vmid) is handled as the conventional "begin" command and
# shows the help menu instead (see process_command_helper.sh).
# File: /usr/bin/telegram_components/commands/start_command.sh
# =============================================================================

start_command() {
    guest_action "$1" "$2" "$3" auto start
}
