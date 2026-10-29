#!/bin/sh
# =============================================================================
# OpenWrt Homelab Power Proxy and Redirection Daemon
# File: /usr/bin/power_proxy_daemon.sh
# =============================================================================

# Load common initialization (paths, config, SSH vars)
. /usr/bin/components/common_init.sh

# Load power_proxy-specific components.
# source_required (components/lib.sh) aborts loudly on a missing/renamed
# component instead of leaving the daemon running half-initialized.
source_required "$PP_COMP/notify_helper.sh"
source_required "$PP_COMP/redirect_helper.sh"
source_required "$PP_COMP/network_helper.sh"
source_required "$PP_COMP/listener_helper.sh"
source_required "$PP_COMP/cleanup_helper.sh"
source_required "$PP_COMP/main.sh"

# Read Config
init_common_config

# Initialize SSH connection parameters
init_ssh_vars

init_daemon_pid "/var/run/power_proxy_daemon.pid" "power_proxy_daemon.sh"

# State variables
CURRENT_STATE="UNKNOWN"
FAILED_PINGS=0
GAME_PIDS=""

IFACE="${LAN_INTERFACE:-br-lan}"

trap cleanup_main SIGTERM SIGINT

# Initialize ARP binding
apply_static_arp

main
