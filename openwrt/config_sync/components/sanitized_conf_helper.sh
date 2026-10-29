#!/bin/sh

sanitize_config() {
    TEMP_CONF="/tmp/power_homelab_pve_sync.conf"
    echo "# =============================================================================" > "$TEMP_CONF"
    echo "# Proxmox VE Idle Monitor Configuration (Auto-Synchronized from OpenWrt)" >> "$TEMP_CONF"
    echo "# Generated on: $(date)" >> "$TEMP_CONF"
    echo "# =============================================================================" >> "$TEMP_CONF"
    echo "" >> "$TEMP_CONF"

    # Filter and extract variables from /etc/power_homelab.conf
    # This strictly keeps only PVE-relevant parameters and avoids leaking secrets
    # Ensure we use the correct config path if $CONF is not set
    local config_path="${CONF:-${ROUTER_CONF:-/etc/power_homelab.conf}}"
    for var in CPU_THRESHOLD SCALE_CPU_THRESHOLD_BY_CORES NET_INTERFACE NET_THRESHOLD_KBPS MONITORED_PORTS \
               HOST_SSH_PORT LXC_SUSPEND_METHOD VM_SUSPEND_METHOD PROTECTED_PROCESSES \
               GUEST_ORCHESTRATION_MAP EXEMPT_SHUTDOWN_GUESTS ACTIVE_TIME_WINDOWS GUEST_NAME_MAP \
               LOG_FILE ENABLE_SYSLOG \
               MONITOR_CPU_THRESHOLD_PCT MONITOR_RAM_THRESHOLD_PCT MONITOR_DISK_THRESHOLD_PCT \
               MONITOR_DISK_PATHS MONITOR_SERVICES MONITOR_ZFS_POOLS MONITOR_CRITICAL_GUESTS \
               MONITOR_COOLDOWN_SEC; do
        # Extract line from config
        val=$(grep -E "^${var}=" "$config_path" 2>/dev/null | head -n 1)
        if [ -n "$val" ]; then
            echo "$val" >> "$TEMP_CONF"
        fi
    done

    echo "Sanitized configuration generated at $TEMP_CONF."
}
