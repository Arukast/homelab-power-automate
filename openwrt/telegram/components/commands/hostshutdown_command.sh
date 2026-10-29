#!/bin/sh
# Thin wrapper → host_power_action (safe shutdown)
hostshutdown_command() {
    host_power_action "$1" "$2" shutdown
}
