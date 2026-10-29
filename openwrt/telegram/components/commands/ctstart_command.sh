#!/bin/sh
# Thin wrapper → guest_action (LXC container start)
ctstart_command() {
    guest_action "$1" "$2" "$3" pct start
}
