#!/bin/sh
# =============================================================================
# OpenWrt Homelab Configuration Synchronization & SSH Trust Verification
# File: /usr/bin/homelab_config_sync.sh
# =============================================================================

# Load common initialization (paths, config, SSH vars)
. /usr/bin/components/common_init.sh

# Load config_sync-specific components (source_required aborts loudly on a
# missing/renamed component instead of silently skipping its step)
source_required "$SYNC_COMP/permission_helper.sh"
source_required "$SYNC_COMP/verify_helper.sh"
source_required "$SYNC_COMP/router_ip_helper.sh"
source_required "$SYNC_COMP/sanitized_conf_helper.sh"
source_required "$SYNC_COMP/deploy_helper.sh"

# Read Config
init_common_config

# Initialize SSH connection parameters (also sets SSH_CMD used by deploy_helper)
init_ssh_vars

echo "===================================================="
echo "Homelab Power Orchestrator Configuration Sync Tool"
echo "===================================================="

# 1. Check local Dropbear private key permissions
check_permission

# 2. Verify passwordless SSH connection & SSH Wrapper status
verify_ssh
ssh_test
ssh_block

# 3. Calculate dynamic Router IP facing Proxmox
get_router_ip

# 4. Generate sanitized configuration file
sanitize_config

# 5. Push the configuration to Proxmox
deploy_config

echo "Sync complete."
exit 0
