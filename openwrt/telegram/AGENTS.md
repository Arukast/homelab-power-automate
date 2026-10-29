# AGENTS.md — openwrt/telegram/ (Telegram bot)

Pure-shell long-polling bot. Daemon: `telegram_bot_daemon.sh` (procd:
`telegram_bot.init`). Read `openwrt/AGENTS.md` first.

## Boot sequence (`telegram_bot_daemon.sh`)

Sources `components/common_init.sh`, the telegram components, and every
`components/commands/*_command.sh`, then:

1. `init_common_config` (reads `/etc/power_homelab.conf` + messages).
2. `init_ssh_vars`.
3. `init_daemon_pid` — single daemon.
4. Starts **one** Host Liveness Monitor (pid-guarded, reaped on exit).
5. `poll_updates` — the long-poll loop.

## Components

- `message_helper.sh` — `expand_msg` (→ `render_msg`) and `send_message` (thin
  wrapper over `tg_send`). No inline keyboards: buttons were removed.
- `process_command_helper.sh` — `process_command` (table dispatch) and
  `process_action` (legacy callback routing only).
- `command_helper.sh` — `guest_action`, `host_power_action`, the maintenance/alive
  guards, and `_guest_probe`/`_guest_require`.
- `polling_helper.sh` — `getUpdates` loop; offset persisted to
  `/var/run/telegram_offset`; callback routing.
- `liveness_monitor.sh` — host ONLINE/OFFLINE transitions, deduped via
  `/var/run/telegram_liveness_state`.
- `maintenance_helper.sh` — `/etc/homelab_maintenance` flag files.
- `commands/*_command.sh` — one file per command; guest commands are thin wrappers
  over `guest_action`.

## Command surface

- **Unified guest control:** `/start|/stop|/restart <vmid>` → `guest_action … auto`.
  The type (pct/qm) is resolved from the VMID (Proxmox VMIDs are unique across VMs
  and containers). Bare `/start` shows help (Telegram convention).
- **Explicit guest control:** `/node <vm|ct> <vmid> <start|stop|restart>` forces the
  type and delegates to `guest_action` (reports a type mismatch instead of a raw
  `qm`/`pct` error).
- **Host power:** `/sleep|/sleepforce|/hostshutdown|/hostshutdownforce|/hostreboot|
  /hostrebootforce` → `host_power_action`. Force variants bypass the safety checks
  but still honour the host run-lock (they report BUSY).
- `/maintenance` is self-documenting (a bare invocation prints usage).
- `/wake` reports "already ONLINE" instead of sending a pointless magic packet.

## Rules

- No bashisms (ash). Handler signature: `(chat_id, message_id [, arg])`.
- Dispatch is a table (`CMD_DISPATCH_TABLE`); add simple commands there, not with
  new `case` arms. Multi-argument commands (`/start`, `/node`, `/maintenance`) are
  handled explicitly in `process_command`.
- **`send_message` arity:** always `send_message "$chat_id" "$text" "" "$msg_id"`.
  The 3rd argument is the (now ignored) markup slot; putting `msg_id` there
  silently breaks delivery.
- Message placeholders: `$arg1..$arg4`, `$HOST_MAC`, `$GUEST_NAME`, `$VMID`,
  `$USER_ID`, `$PORT_RAW`, `$GUEST_IP`. Templates live in
  `../messages_homelab.conf`; every referenced key must be defined there or it
  renders empty.
- `curl` calls need timeouts; `tg_send` already does the Markdown→plain retry.
- Keep exactly one liveness monitor; transitions are deduped so duplicates cannot
  double-notify even if a stale monitor survives.
