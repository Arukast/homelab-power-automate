# AGENTS.md — homelab-powerorchestractor

Guidance for coding agents working in this repository. Read this file first, then
the nearest `AGENTS.md` in the directory you are touching.

## What this is

A zero-cloud, shell-based power-orchestration suite for a homelab:

- **`proxmox/`** — runs as root on Proxmox VE (systemd). Suspends the host to S3
  when idle, stops/shuts down guests, monitors resources, and exposes the
  restricted SSH command gateway (`homelab_ssh_wrapper.sh`).
- **`openwrt/`** — runs on an OpenWrt router (procd). A Telegram control bot, a
  Wake-on-Demand proxy, and the config-sync tool that pushes config to Proxmox.

The router is the control plane and the single source of truth for configuration.

## Golden rules

Each rule exists because breaking it caused a real incident (see "Rule → why").

1. **Shell dialect per zone.** `openwrt/**` is BusyBox **ash / POSIX sh**:
   `#!/bin/sh`, no bashisms (`[[ ]]`, `==` inside `[ ]`, `${var:0:2}`), no `jq`.
   `proxmox/**` may use bash (bash is present on Proxmox VE).
2. **The SSH wire protocol is a contract.** The router sends exact command
   strings; `proxmox/homelab_ssh_wrapper.sh` matches them **literally**. Never
   change a sent string without updating the wrapper allow-list (and vice versa).
3. **Never execute config data.** On Proxmox, load config with `load_conf` /
   `load_msg_conf` (allow-listed `KEY=` readers) and render templates with
   `render_msg` (parameter expansion). Do **not** `source`/`.` config files and do
   **not** `eval echo` message templates.
4. **Bound every external call.** `curl` needs `--connect-timeout`/`--max-time`;
   host probes need a timeout. An unbounded SSH connect to a sleeping host hangs
   for the kernel TCP timeout (~2 min).
5. **Canonical config paths.** Constants live in `openwrt/components/lib.sh`
   (`ROUTER_CONF`, `MSG_CONF`, `PVE_CONF`):
   - Router: `/etc/power_homelab.conf`, messages `/etc/messages_homelab.conf`
   - Proxmox: `/etc/homelab_power.conf`, messages `/etc/homelab_messages.conf`
   - The Proxmox config is pushed from the router by `homelab_config_sync.sh`; it
     is not edited on the host.
6. **Never commit secrets.** `openwrt/power_homelab.conf` is gitignored and holds
   live tokens; `power_homelab.conf.example` is the template.

## Cross-zone protocol: the `--check` pre-flight

Safe power actions (`/sleep`, `/hostshutdown`, `/hostreboot`; the `force` variants
only use it to detect BUSY) ask the host first:

- Router: `ssh … '/usr/local/bin/proxmox_idle_monitor.sh --check'`
- Host (`REPORT_ONLY=1`) prints exactly **one** machine-readable line and does
  nothing:
  `HOMELAB_CHECK:BLOCKED: <reason>` | `HOMELAB_CHECK:IDLE` |
  `HOMELAB_CHECK:BUSY` | `HOMELAB_CHECK:UNSUPPORTED`
- `--check` must stay **side-effect free**: no guest actions, no idle-timer
  writes, no lock acquisition (it only *probes* the lock).
- The wrapper allow-lists the exact `--check` string, and refuses to run it
  against a monitor that predates `--check` (returns `UNSUPPORTED`) so a stale
  monitor can never accidentally perform the real action.

## Testing

```sh
./test_suite.sh
```

- It sources the **real** libraries (`proxmox/lib.sh`, `openwrt/components/lib.sh`)
  — do not re-implement logic in tests; that is how real bugs previously shipped.
- Add a regression test for every bug you fix.
- Also run `sh -n` on changed `openwrt/**` files and `bash -n` on `proxmox/**`.

## Deployment (not part of a code change)

- **Router:** copy `openwrt/` to the router, run `install/install_openwrt.sh`,
  then `/etc/init.d/telegram_bot restart` and `/etc/init.d/power_proxy restart`.
- **Proxmox:** copy `proxmox/` and run `install_proxmox.sh` as root (it preserves
  an existing `/etc/homelab_power.conf`).
- Deploy from the working tree; a git clone/pull will not contain uncommitted work.

## Rule → why

- Unbounded SSH probe → `/wake` took ~3 min on a sleeping host (static ARP
  blackholes SYNs).
- `flock` on an inherited fd → `kvm` held the lock for the VM's lifetime; every
  later run (timer included) bailed out.
- `nohup … &` from the SSH session → logind killed manual actions while the
  systemd-timer path still worked.
- `qm shutdown` without `--timeout` → a reboot appeared to hang for minutes.
- `source` of config / `eval echo` templates → root RCE via the router SSH key.
- `local PATH=…` → shadowed `PATH` and broke `date`/`grep`/`curl` in the resource
  monitor.
- `cut -d' ' -f2-` on a bare command → `/maintenance` was parsed as its own
  sub-command.
- Duplicate liveness monitors → doubled ONLINE/OFFLINE notifications.
- `redirects_helper.sh` typo (file is `redirect_helper.sh`) → the whole
  Wake-on-Demand proxy was silently dead.

## Where to go next

- `proxmox/AGENTS.md` — host-side rules (wrapper, idle monitor, lock, loaders).
- `openwrt/AGENTS.md` — router-side rules (procd, shared lib, module layout).
- `openwrt/telegram/AGENTS.md` — the bot (dispatch, handlers, messages).
- `openwrt/power_proxy/AGENTS.md` — Wake-on-Demand proxy and listeners.
- `openwrt/config_sync/AGENTS.md` — config/SSH-trust bridge to Proxmox.
