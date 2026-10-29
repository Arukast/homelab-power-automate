# AGENTS.md — proxmox/ (host side, runs as root)

Systemd-managed scripts installed to `/usr/local`. **Bash is allowed here**
(Proxmox VE has bash). Read the repository-root `AGENTS.md` first for the
cross-zone rules.

## File map

- `proxmox_idle_monitor.sh` — idle detection → guest stop/suspend → S3 sleep;
  also `--shutdown`, `--reboot`, `--force`, and `--check` (read-only pre-flight).
- `proxmox_resource_monitor.sh` — CPU/RAM/disk/ZFS/service/guest alerts.
- `homelab_ssh_wrapper.sh` — the forced-command gateway in `authorized_keys`; the
  **only** trust boundary between the router's SSH key and root.
- `lib.sh` — `log`, `notify`, `render_msg`, `load_conf`, `load_msg_conf`,
  `to_integer`, `day_to_num`, `is_in_active_window`.
- `install_proxmox.sh` — installs `lib.sh` to `/usr/local/lib/homelab/`, the
  scripts to `/usr/local/{bin,lib}`, and the systemd units; seeds config only.
- `*.service` / `*.timer` — systemd units.

## Rules

1. **Never `source` the config.** Use `load_conf "$CONF"` / `load_msg_conf
   "$MSG_CONF"`; they only apply allow-listed `KEY=` lines after validation.
   Sourcing a config written by the router is root RCE.
2. **Never `eval echo` templates.** Use `render_msg` (pure parameter expansion).
   Templates may reference `$GUEST_NAME $VMID $TIMEOUT_MIN $VALUE $THRESHOLD
   $PATH $SERVICE $POOL`. The disk path is passed as **`HL_PATH`**, never `PATH`
   — a local named `PATH` shadows the command search path and breaks
   `date`/`grep`/`mv`/`curl`.
3. **Lock with a directory, not `flock` on an fd.** Use
   `/run/proxmox_idle_monitor.lock.d` (mkdir + pid + stale takeover). `flock` on
   fd 9 leaks into `qm`/`pct` children and is held by `kvm` for the VM's whole
   lifetime. `--check` only probes it (non-blocking) and reports `BUSY`.
4. **The wrapper matches command strings literally.** If the router starts
   sending a new string, add the exact `case` arm. Manual launches go through
   `run_idle_monitor` (which uses `systemd-run`) so the monitor survives the SSH
   session — a plain `nohup … &` can be killed by logind.
5. **Config pushes are validated.** The wrapper's `cat > /etc/homelab_power.conf`
   path rejects any non-comment line outside `^[A-Z_][A-Z0-9_]*="?[A-Za-z0-9 ,._/:+=-]*"?$`
   and installs the file mode `0600`. The `--check` arm refuses to run a monitor
   that lacks `REPORT_ONLY` (returns `HOMELAB_CHECK:UNSUPPORTED`).
6. **Bound guest shutdowns.** `qm shutdown` blocks up to 180 s by default — always
   pass `--timeout` and run VM shutdowns in parallel, or a reboot looks hung.
7. **`--check` is side-effect free.** No guest suspends, no idle-timer writes, no
   lock acquisition; emit exactly one `HOMELAB_CHECK:` line and exit.

## Semantics worth knowing

- `ACTIVE_TIME_WINDOWS` (synced from the router) makes the idle monitor skip
  checks inside the window; `--check` reports it as a block reason.
- `--shutdown`/`--reboot` switch guest methods to stop/shutdown and then perform
  the host action; the wake-up section only runs after an S3 resume.
- Guest exemption (`EXEMPT_SHUTDOWN_GUESTS`) affects *blocking* decisions, not the
  stop/shutdown loop.

## Deploy

Copy this directory and run `install_proxmox.sh` as root. It preserves an existing
`/etc/homelab_power.conf`, which is managed from the router via
`homelab_config_sync.sh`.
