#!/bin/sh

deploy_config() {
    echo "Deploying configuration to Proxmox..."
    if [ "$WRAPPER_ACTIVE" -eq 1 ]; then
        # Push via cat redirect permitted by wrapper
        $SSH_CMD "cat > /etc/homelab_power.conf" < "$TEMP_CONF"
    else
        # Fallback to standard scp if wrapper is not configured yet
        scp -P "$HOST_SSH_PORT" -i "$SSH_KEY_PATH" "$TEMP_CONF" ${HOST_SSH_USER}@$HOST_IP:/etc/homelab_power.conf >/dev/null
    fi


    if [ $? -eq 0 ]; then
        echo "Configuration successfully synchronized to Proxmox /etc/homelab_power.conf."
        # Trigger systemd reload/restart on PVE if timers are active
        $SSH_CMD "systemctl restart proxmox_idle_monitor.timer" >/dev/null 2>&1 || true
        $SSH_CMD "systemctl restart proxmox_resource_monitor.timer" >/dev/null 2>&1 || true
    else
        echo "Error: Failed to write configuration to Proxmox." >&2
        exit 1
    fi
}
