#!/bin/sh
# Thin wrapper → host_power_action (safe sleep)
sleep_command() {
    host_power_action "$1" "$2" sleep
}
