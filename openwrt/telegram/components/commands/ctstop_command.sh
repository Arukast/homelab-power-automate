#!/bin/sh
# Thin wrapper → guest_action (LXC container stop)
ctstop_command() {
    guest_action "$1" "$2" "$3" pct stop
}
