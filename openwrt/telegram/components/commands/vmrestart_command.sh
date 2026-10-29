#!/bin/sh
# Thin wrapper → guest_action (QEMU VM restart)
vmrestart_command() {
    guest_action "$1" "$2" "$3" qm reboot
}
