#!/bin/sh
# Thin wrapper → guest_action (QEMU VM start)
vmstart_command() {
    guest_action "$1" "$2" "$3" qm start
}
