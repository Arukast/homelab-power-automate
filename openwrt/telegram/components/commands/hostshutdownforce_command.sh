#!/bin/sh
# Thin wrapper → host_power_action (forced shutdown)
hostshutdownforce_command() {
    host_power_action "$1" "$2" shutdownforce
}
