#!/bin/bash
# =============================================================================
# Proxmox VE Power Saver Installer Script
# File: PowerOrchestrator/proxmox/install_proxmox.sh
# Run this script on the Proxmox host as root.
# =============================================================================

set -e

# Change directory to the script's location
cd "$(dirname "$0")"

# Parse command line arguments
FORCE_CONFIG=0
for arg in "$@"; do
    if [ "$arg" = "-f" ] || [ "$arg" = "--force" ]; then
        FORCE_CONFIG=1
    fi
done

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}Installing Homelab Power Saver Suite on Proxmox VE  ${NC}"
echo -e "${BLUE}====================================================${NC}"

# Check root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This installer must be run as root!${NC}" >&2
    exit 1
fi

# 1. Install dependencies
echo -e "${GREEN}[1/5] Checking dependencies...${NC}"
DEPS=""
if ! command -v bc >/dev/null 2>&1; then
    DEPS="bc"
fi
if ! command -v conntrack >/dev/null 2>&1; then
    DEPS="$DEPS conntrack"
fi
if ! command -v tcpdump >/dev/null 2>&1; then
    DEPS="$DEPS tcpdump"
fi

if [ -n "$DEPS" ]; then
    echo "Installing missing dependencies:$DEPS..."
    apt-get update -qy && apt-get install -qy $DEPS
else
    echo "All dependencies (bc, conntrack, tcpdump) are already installed."
fi

# 2. Copy configuration file
echo -e "${GREEN}[2/5] Setting up configuration...${NC}"
if [ -f "/etc/homelab_power.conf" ] && [ "$FORCE_CONFIG" -ne 1 ]; then
    echo "Configuration file /etc/homelab_power.conf already exists. Preserving it."
    echo "Run this installer with the -f or --force flag to overwrite it with your laptop's version."
else
    if [ -f "homelab_power.conf" ]; then
        cp homelab_power.conf /etc/homelab_power.conf
        echo "Created/Overwrote /etc/homelab_power.conf from your custom local config file."
    else
        cp homelab_power.conf.example /etc/homelab_power.conf
        echo "Created/Overwrote /etc/homelab_power.conf from the default template."
    fi
    chmod 600 /etc/homelab_power.conf
fi

# 3. Copy scripts
echo -e "${GREEN}[3/5] Installing shared library & core monitoring/wrapper scripts...${NC}"
mkdir -p /usr/local/lib/homelab
cp lib.sh /usr/local/lib/homelab/lib.sh
chmod 644 /usr/local/lib/homelab/lib.sh
echo "Installed /usr/local/lib/homelab/lib.sh"

cp proxmox_idle_monitor.sh /usr/local/bin/proxmox_idle_monitor.sh
chmod 755 /usr/local/bin/proxmox_idle_monitor.sh
echo "Installed /usr/local/bin/proxmox_idle_monitor.sh"

cp proxmox_resource_monitor.sh /usr/local/bin/proxmox_resource_monitor.sh
chmod 755 /usr/local/bin/proxmox_resource_monitor.sh
echo "Installed /usr/local/bin/proxmox_resource_monitor.sh"

cp homelab_ssh_wrapper.sh /usr/local/bin/homelab_ssh_wrapper.sh
chmod 755 /usr/local/bin/homelab_ssh_wrapper.sh
echo "Installed /usr/local/bin/homelab_ssh_wrapper.sh"

# 4. Copy systemd units
echo -e "${GREEN}[4/5] Registering systemd services...${NC}"
cp proxmox_idle_monitor.service /etc/systemd/system/
cp proxmox_idle_monitor.timer /etc/systemd/system/
cp proxmox_resource_monitor.service /etc/systemd/system/
cp proxmox_resource_monitor.timer /etc/systemd/system/

chmod 644 /etc/systemd/system/proxmox_idle_monitor.service
chmod 644 /etc/systemd/system/proxmox_idle_monitor.timer
chmod 644 /etc/systemd/system/proxmox_resource_monitor.service
chmod 644 /etc/systemd/system/proxmox_resource_monitor.timer

# Reload systemd
systemctl daemon-reload

# 5. Enable and start timer
echo -e "${GREEN}[5/5] Activating systemd timers...${NC}"
systemctl enable --now proxmox_idle_monitor.timer
systemctl enable --now proxmox_resource_monitor.timer

echo -e "${BLUE}====================================================${NC}"
echo -e "${GREEN}Installation Successful!${NC}"
echo -e "You can configure thresholds and monitored ports in:"
echo -e "   ${BLUE}/etc/homelab_power.conf${NC}"
echo -e ""
echo -e "To view logs, run:"
echo -e "   ${BLUE}tail -f /var/log/proxmox_power.log${NC}"
echo -e "or"
echo -e "   ${BLUE}journalctl -u proxmox_idle_monitor.service${NC}"
echo -e ""
echo -e "To manually trigger an idle check and suspend immediately if idle:"
echo -e "   ${BLUE}systemctl start proxmox_idle_monitor.service${NC}"
echo -e "${BLUE}====================================================${NC}"
