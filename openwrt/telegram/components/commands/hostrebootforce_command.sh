#!/bin/sh
# Thin wrapper → host_power_action (forced reboot)
hostrebootforce_command() {
    host_power_action "$1" "$2" rebootforce
}
