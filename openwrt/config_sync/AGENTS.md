# AGENTS.md — openwrt/config_sync/ (config + SSH-trust bridge)

Ships the router's configuration to Proxmox and verifies the restricted SSH
channel. Entry point: `homelab_config_sync.sh`. This is security-sensitive — read
`openwrt/AGENTS.md` and the root `AGENTS.md` first.

## Flow (`homelab_config_sync.sh`)

1. `components/permission_helper.sh` — ensure the Dropbear private key is `0600`.
   Checks the **full** mode via `ls -l` (not `stat -c`, which is unreliable on some
   OpenWrt builds), and fixes it if needed.
2. `components/verify_helper.sh` — `ssh_test` (accepts a bare `OK` line even if
   Dropbear emitted a warning on stderr) and `ssh_block` (detects the wrapper by
   expecting `Access Denied` when running `uname`).
3. `components/router_ip_helper.sh` — compute the router address facing Proxmox.
4. `components/sanitized_conf_helper.sh` — build `/tmp/power_homelab_pve_sync.conf`
   from an **allow-list** of keys; secrets never leave the router.
5. `components/deploy_helper.sh` — push via `cat > /etc/homelab_power.conf` (the
   wrapper validates it) with an `scp` fallback, then restart the PVE timers.

## Rules

- The Proxmox `/etc/homelab_power.conf` **is the router's sanitized config**. Do not
  add secret keys to the whitelist and do not treat the PVE file as authoritative.
- The wrapper validates the pushed payload against
  `^[A-Z_][A-Z0-9_]*="?[A-Za-z0-9 ,._/:+=-]*"?$`. Keep syncable values inside that
  charset or the push is rejected.
- Dropbear's `ssh` rejects OpenSSH-only options — do not add `-o ConnectTimeout=…`.
- Keep the temporary config file private and never log secrets.
