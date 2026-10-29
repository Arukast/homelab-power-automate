#!/bin/sh
# Thin wrapper → host_power_action (safe reboot)
hostreboot_command() {
    host_power_action "$1" "$2" reboot
}
