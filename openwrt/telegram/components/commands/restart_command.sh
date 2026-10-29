#!/bin/sh
# =============================================================================
# /restart Bot Command Handler (guest restart)
#   /restart <vmid>  — restarts a VM or LXC; the type is auto-detected from the
#   VMID. Mapped to the Proxmox `reboot` verb.
# File: /usr/bin/telegram_components/commands/restart_command.sh
# =============================================================================

restart_command() {
    guest_action "$1" "$2" "$3" auto reboot
}
