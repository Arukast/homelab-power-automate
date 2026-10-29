# AGENTS.md — openwrt/power_proxy/ (Wake-on-Demand)

Keeps a sleeping Proxmox host reachable on demand: redirects web traffic and
fires Wake-on-LAN when a client hits a monitored port. Daemon:
`power_proxy_daemon.sh` (procd: `power_proxy.init`, which checks `ROUTER_CONF`).
Read `openwrt/AGENTS.md` first.

## Layout and source order

`power_proxy_daemon.sh` sources components in this order (dependency order matters):
`notify_helper.sh` → `redirect_helper.sh` → `network_helper.sh` →
`listener_helper.sh` → `cleanup_helper.sh` → `main.sh`.

- `components/main.sh` — state loop (UP / DOWN); applies/removes redirects and
  starts game + guest listeners.
- `components/redirect_helper.sh` — `apply_redirects` / `remove_redirects` (nft, or
  iptables fallback). **Note the singular filename** — a `redirects_helper.sh` typo
  here once left the whole proxy dead.
- `components/listener_helper.sh` — `listen_game` / `listen_guest`, `send_wol`
  (with cooldown), and bounded `wait_for_host_boot` / `wait_for_game_boot`.
- `components/network_helper.sh` — `bind_ip`, `apply_static_arp`, `parse_port`.
- `components/cleanup_helper.sh` — SIGTERM/SIGINT trap handlers.
- `components/notify_helper.sh` — delegates to `/usr/bin/homelab_notify.sh`.
- `game_wake_listener.sh` / `guest_wake_listener.sh` — per-port listeners.

## Rules

- POSIX sh only. Every sourced file must exist — `power_proxy_daemon.sh` uses
  `source_required`, so a renamed file fails loudly instead of silently.
- `apply_static_arp` pins `HOST_IP -> HOST_MAC`. That is why probes to a sleeping
  host blackhole: **bound every network call with a timeout**.
- Wake listeners: cap the boot-wait loop and re-send WoL periodically; use the
  cooldown in `send_wol` so a bind failure or `-w` timeout cannot spam magic
  packets.
- Do not call `cleanup_guest` inline — it ends in `exit 0`; rely on the trap.
- Keep `ip addr`/nft rule changes symmetric (add and remove), and clean up on
  SIGTERM/SIGINT so no stale aliases or NAT rules survive.
- The bot writes `/tmp/homelab_target_state` (`SLEEP`/`SHUTDOWN`/`REBOOT`); `main.sh`
  reads it to decide between redirect-to-waking-page and "host offline".
