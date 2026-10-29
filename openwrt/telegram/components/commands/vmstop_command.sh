#!/bin/sh
# Thin wrapper → guest_action (QEMU VM stop)
vmstop_command() {
    guest_action "$1" "$2" "$3" qm stop
}
