# AGENTS.md — openwrt/ (router control plane)

OpenWrt / BusyBox **ash**. Everything here ships to `/usr/bin` and runs under
procd. Read the repository-root `AGENTS.md` first.

## Layout

- **`components/`** — shared, sourced by every entry point via `common_init.sh`:
  - `lib.sh` — `ROUTER_CONF`/`MSG_CONF`/`PVE_CONF`, `trim`, `render_msg`,
    `tg_send`, `source_required`, `log_router`.
  - `common_init.sh` — exports `SHARED_COMP`/`PP_COMP`/`TB_COMP`/`SYNC_COMP`;
    `init_common_config`, `init_ssh_vars` (`SSH_CMD`), `init_daemon_pid`.
  - `conf_helper.sh` — `read_conf`, `read_optional_conf`, `check_ip`.
  - `check_helper.sh` — `is_host_alive`, `is_pid_running`, token check.
- **`telegram/`** — the bot. See `telegram/AGENTS.md`.
- **`power_proxy/`** — Wake-on-Demand. See `power_proxy/AGENTS.md`.
- **`config_sync/`** — config + SSH-trust sync to Proxmox. See `config_sync/AGENTS.md`.
- **`install/`** — installer and `install/components/*`.
- `power_homelab.conf(.example)` — router configuration + template.
- `messages_homelab.conf` — `MSG_*` notification/response templates.

## Rules

- **POSIX sh only.** Prefer the shared helpers (`render_msg`, `trim`, `tg_send`)
  instead of re-implementing them. No `jq`; no bashisms.
- **`is_host_alive` must stay cheap and bounded:** ICMP → bounded curl
  (`--connect-timeout 1`) → SSH *only when `timeout` exists*. Never add an
  unbounded probe — a sleeping host blackholes SYNs because of the permanent
  static ARP entry. (`/wake` once blocked ~3 minutes because of this.)
- **`SSH_CMD` is a space-joined string** used as `$SSH_CMD "remote command"`. Do
  not add OpenSSH-only options: OpenWrt's `ssh` is Dropbear, which rejects
  `-o ConnectTimeout=…` and prints a warning that pollutes command output.
- Daemons are procd services defined in the adjacent `*.init` files; the router
  config path is `/etc/power_homelab.conf` (`lib.sh`'s `ROUTER_CONF`).
- **Adding a config key:** add it to `power_homelab.conf.example`; add it to the
  PVE sync whitelist (`config_sync/components/sanitized_conf_helper.sh`) *only* if
  Proxmox needs it. Never sync secrets.
- **Adding a script:** the installer copies whole directories —
  `components/*`, `power_proxy/components/*`, `telegram/components/*` +
  `telegram/components/commands/*`, `config_sync/components/*`. Keep files inside
  those directories so they are deployed automatically.

## Deploy

Copy this tree to the router, run `install/install_openwrt.sh`, then restart
`telegram_bot` and `power_proxy`.
