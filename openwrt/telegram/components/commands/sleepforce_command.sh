#!/bin/sh
# Thin wrapper → host_power_action (forced sleep)
sleepforce_command() {
    host_power_action "$1" "$2" sleepforce
}
