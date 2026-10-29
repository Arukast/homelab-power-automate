#!/bin/sh
# Thin wrapper → guest_action (LXC container restart)
ctrestart_command() {
    guest_action "$1" "$2" "$3" pct reboot
}
