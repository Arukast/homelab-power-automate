#!/bin/bash
# =============================================================================
# Proxmox VE Idle Monitor & ACPI S3 Suspend Script
# File: /usr/local/bin/proxmox_idle_monitor.sh
# =============================================================================

# Default Config Path
CONF="/etc/homelab_power.conf"
# Notification messages config (deployed to PVE by the router's config_sync tool).
MSG_CONF="/etc/homelab_messages.conf"

# Syslog tag for this monitor's log()/notify() calls (see lib.sh)
LOG_TAG="proxmox-idle-monitor"

# Default fallback values
CPU_THRESHOLD="0.15"
SCALE_CPU_THRESHOLD_BY_CORES=1
NET_INTERFACE="vmbr0"
NET_THRESHOLD_KBPS="50"
HOST_SSH_PORT="${HOST_SSH_PORT:-${SSH_PORT:-22}}"
MONITORED_PORTS="25565,32400,8006,8123,${HOST_SSH_PORT}"
LXC_SUSPEND_METHOD="suspend"
VM_SUSPEND_METHOD="suspend"
PROTECTED_PROCESSES="vzdump qm pct rsync proxmox-backup-client apt-get dpkg"
LOG_FILE="/var/log/proxmox_power.log"
ENABLE_SYSLOG=1

# Default fallback messages (if /etc/homelab_messages.conf is not present)
MSG_PROXMOX_GUEST_SUSPENDED='[Guest Idle Sleep] Service $GUEST_NAME (VMID $VMID) was idle for $TIMEOUT_MIN minutes and has been successfully suspended to reclaim system resources!'
MSG_PROXMOX_GUEST_STOPPED='[Guest Idle Sleep] Service $GUEST_NAME (VMID $VMID) was idle for $TIMEOUT_MIN minutes and has been stopped cleanly to reclaim system resources!'
MSG_PROXMOX_HOST_SLEEPING='[Proxmox Host Sleeping] Host is entering S3 Suspend-to-RAM. All system states successfully saved!'
MSG_PROXMOX_HOST_AWAKE='[Proxmox Host Awake] Host successfully woke up from ACPI S3 sleep. Restoring all guest VMs...'

# --- Shared library (hardened config loaders + helpers) ---
# Installed to /usr/local/lib/homelab/lib.sh; fall back to the script's own
# directory so it can also be exercised straight from the repository.
LIB_FILE="/usr/local/lib/homelab/lib.sh"
[ -f "$LIB_FILE" ] || LIB_FILE="$(dirname "$0")/lib.sh"
# shellcheck source=lib.sh
. "$LIB_FILE"

# Load configuration if exists. load_conf() only applies allowlisted "KEY="
# assignments after strict validation - it never `source`s the file, because
# doing so as root would let anyone holding the router SSH key run arbitrary
# code as root on the Proxmox host.
load_conf "$CONF"

# Load messages configuration if exists
load_msg_conf "$MSG_CONF"

# --- Helper functions (log, notify, render_msg, to_integer, day_to_num,
# --- is_in_active_window, load_conf) live in proxmox/lib.sh.

# Ensure log file exists
touch "$LOG_FILE"

# Parse arguments.
#   --check : run the idle checks and REPORT the verdict WITHOUT acting. It is
#             read-only (no guest suspension, no lock) and is used by the
#             Telegram bot to explain why a safe action was refused.
FORCE_SLEEP=0
REPORT_ONLY=0
ACTION="suspend"

for arg in "$@"; do
    case "$arg" in
        --force|force)       FORCE_SLEEP=1 ;;
        --shutdown|shutdown) ACTION="shutdown" ;;
        --reboot|reboot)     ACTION="reboot" ;;
        --check|check)       REPORT_ONLY=1 ;;
    esac
done

# --- Single-instance lock -----------------------------------------------------
# This script is launched both by proxmox_idle_monitor.timer and on demand by the
# Telegram command handlers; two concurrent runs could double-suspend guests.
#
# Deliberately NOT `flock` on an inherited fd: an open fd is inherited by every
# child, and `qm`/`pct` leave it open in the QEMU/LXC process, so the lock ends up
# held by `kvm` for the VM's whole lifetime and every later run (timer included)
# bails out. A directory lock is atomic and never leaks into children.
LOCKDIR="/run/proxmox_idle_monitor.lock.d"

lock_holder_alive() {
    _h=$(cat "$LOCKDIR/pid" 2>/dev/null)
    [ -n "$_h" ] && kill -0 "$_h" 2>/dev/null
}

if [ "$REPORT_ONLY" -eq 1 ]; then
    # --check never takes the lock; it only reports a busy host.
    if [ -d "$LOCKDIR" ] && lock_holder_alive; then
        printf 'HOMELAB_CHECK:BUSY\n'
        exit 0
    fi
else
    _waited=0
    _stale=0
    while ! mkdir "$LOCKDIR" 2>/dev/null; do
        if [ -d "$LOCKDIR" ] && ! lock_holder_alive; then
            # Stale lock left by a crashed/killed run - take it over.
            _stale=$((_stale + 1))
            if [ "$_stale" -le 5 ]; then
                rm -rf "$LOCKDIR" 2>/dev/null
                continue
            fi
        fi
        _waited=$((_waited + 1))
        if [ "$_waited" -ge 60 ]; then
            log "another instance is running; exiting"
            exit 0
        fi
        sleep 1
    done
    echo $$ > "$LOCKDIR/pid" 2>/dev/null
    trap 'rm -rf "$LOCKDIR" 2>/dev/null' EXIT INT TERM
fi

# Report the reason the host is NOT idle and stop. In --check mode the reason is
# also emitted on a machine-readable line so the Telegram bot can surface it.
blocked() {
    log "BLOCK: $1"
    if [ "$REPORT_ONLY" -eq 1 ]; then
        printf 'HOMELAB_CHECK:BLOCKED: %s\n' "$1"
    fi
    exit 0
}

# If the target host action is shutdown or reboot, we MUST stop guests rather than S3-suspending to RAM!
if [ "$ACTION" = "shutdown" ] || [ "$ACTION" = "reboot" ]; then
    log "Host action is $ACTION. Overriding guest suspension methods to safe stop/shutdown..."
    LXC_SUSPEND_METHOD="stop"
    VM_SUSPEND_METHOD="shutdown"
fi

if [ "$FORCE_SLEEP" -eq 1 ]; then
    log "=== Manual Force Action Triggered: $ACTION ==="
else
    log "=== Running Idle Check Cycle for Action: $ACTION ==="
fi

# Run activity and idle checks only if not forced
if [ "$FORCE_SLEEP" -eq 0 ]; then
    if is_in_active_window; then
        blocked "current time is within the scheduled awake window ($ACTIVE_TIME_WINDOWS)"
    fi

# 0. Individual Guest Auto-Sleep Check
if [ -n "$GUEST_ORCHESTRATION_MAP" ]; then
    log "Checking individual guest idle states..."
    STATE_FILE="/tmp/proxmox_guest_idle_states"
    touch "$STATE_FILE"
    CURRENT_TIME=$(date +%s)
    
    NEW_STATES=""
    ORCHESTRATED_GUESTS_RUNNING=0
    
    for entry in $(echo "$GUEST_ORCHESTRATION_MAP" | tr ',' ' '); do
        VMID=$(echo "$entry" | cut -d':' -f1)
        GUEST_IP=$(echo "$entry" | cut -d':' -f2)
        PORT_RAW=$(echo "$entry" | cut -d':' -f3)
        TIMEOUT_MIN=$(echo "$entry" | cut -d':' -f4)

        # --- Validate the map entry (task 2.8) ---
        # A malformed entry must never reach the arithmetic below: "abc" would
        # throw "integer expression expected" and could keep the host awake
        # forever. Skip bad entries with a warning instead.
        if ! echo "$VMID" | grep -qE '^[0-9]+$'; then
            log "WARNING: Skipping malformed GUEST_ORCHESTRATION_MAP entry '$entry' (invalid VMID)."
            continue
        fi
        if ! echo "$GUEST_IP" | grep -qE '^[0-9A-Za-z._:-]+$'; then
            log "WARNING: Skipping malformed GUEST_ORCHESTRATION_MAP entry '$entry' (invalid IP/host)."
            continue
        fi
        if ! echo "$PORT_RAW" | grep -qE '^[0-9]+(/[A-Za-z]+)?(\+[0-9]+(/[A-Za-z]+)?)*$'; then
            log "WARNING: Skipping malformed GUEST_ORCHESTRATION_MAP entry '$entry' (invalid port spec)."
            continue
        fi
        # TIMEOUT_MIN must be a non-negative integer; otherwise default to 0
        # (monitor-only mode).
        if ! echo "$TIMEOUT_MIN" | grep -qE '^[0-9]+$'; then
            log "WARNING: GUEST_ORCHESTRATION_MAP entry '$entry' has an invalid idle timeout '${TIMEOUT_MIN}'; defaulting to 0."
            TIMEOUT_MIN=0
        fi

        GUEST_RUNNING=0
        if pct status "$VMID" >/dev/null 2>&1; then
            if [ "$(pct status "$VMID" | awk '{print $2}')" = "running" ]; then
                GUEST_RUNNING=1
            fi
        elif qm status "$VMID" >/dev/null 2>&1; then
            if [ "$(qm status "$VMID" | awk '{print $2}')" = "running" ]; then
                GUEST_RUNNING=1
            fi
        fi
        
        if [ "$GUEST_RUNNING" -eq 1 ]; then
            ORCHESTRATED_GUESTS_RUNNING=$((ORCHESTRATED_GUESTS_RUNNING + 1))
            CONN_COUNT=0
            
            # Support multiple ports separated by + (e.g. 25565/tcp+19132/udp)
            for sub_port in $(echo "$PORT_RAW" | tr '+' ' '); do
                sub_port_num=$(echo "$sub_port" | cut -d'/' -f1)
                sub_proto=$(echo "$sub_port" | cut -d'/' -f2 -s)
                [ -z "$sub_proto" ] && sub_proto="tcp"
                
                sub_count=0
                # Check based on guest type (LXC vs QEMU VM)
                if pct status "$VMID" >/dev/null 2>&1; then
                    # LXC Container: query network namespace directly
                    sub_count=$(pct exec "$VMID" -- ss -tuan state established 2>/dev/null | grep -c -E ":${sub_port_num}[[:space:]]")
                    if [ $? -ne 0 ] || [ -z "$sub_count" ] || [ "$sub_count" -eq 0 ]; then
                        # Fallback: check /proc/net/tcp and /proc/net/udp inside namespace
                        hex_port=$(printf "%04x" "$sub_port_num")
                        if [ "$sub_proto" = "tcp" ]; then
                            sub_count=$(pct exec "$VMID" -- cat /proc/net/tcp 2>/dev/null | awk -v hp="$hex_port" '$3 ~ ":" hp && $4 == "01"' | wc -l)
                        else
                            sub_count=$(pct exec "$VMID" -- cat /proc/net/udp 2>/dev/null | awk -v hp="$hex_port" '$3 ~ ":" hp && $4 != "00000000:0000"' | wc -l)
                        fi
                    fi
                elif qm status "$VMID" >/dev/null 2>&1; then
                    # QEMU VM
                    # Method A: Check via QEMU Guest Agent (if active)
                    if qm guest cmd "$VMID" ping >/dev/null 2>&1; then
                        guest_out=$(qm guest exec "$VMID" -- ss -tuan state established 2>/dev/null)
                        if [ -n "$guest_out" ]; then
                            b64_data=$(echo "$guest_out" | grep -oE '"out-data"\s*:\s*"[^"]+"' | cut -d'"' -f4)
                            if [ -n "$b64_data" ]; then
                                sub_count=$(echo "$b64_data" | base64 -d 2>/dev/null | grep -c -E ":${sub_port_num}[[:space:]]")
                            fi
                        fi
                    fi
                    
                    # Method B: Fallback to capturing L2 packet flows on VM's virtual tap interface
                    if [ -z "$sub_count" ] || [ "$sub_count" -eq 0 ]; then
                        if [ -d "/sys/class/net/tap${VMID}i0" ]; then
                            if timeout 2 tcpdump -i "tap${VMID}i0" -c 1 -p -n "port ${sub_port_num}" >/dev/null 2>&1; then
                                sub_count=1
                            fi
                        fi
                    fi
                fi
                [ -z "$sub_count" ] && sub_count=0
                CONN_COUNT=$((CONN_COUNT + sub_count))
            done
            
            log "Guest [$VMID] ($GUEST_IP) ports $PORT_RAW active connections: $CONN_COUNT"
            
            if [ "$CONN_COUNT" -eq 0 ]; then
                if [ "$TIMEOUT_MIN" -eq 0 ]; then
                    # Monitor-only mode (TIMEOUT_MIN=0): active connections block the host,
                    # but when idle the guest is NEVER auto-slept and does NOT hold back the host.
                    log "Guest [$VMID] is idle (monitor-only mode, TIMEOUT_MIN=0). Not blocking host sleep."
                    ORCHESTRATED_GUESTS_RUNNING=$((ORCHESTRATED_GUESTS_RUNNING - 1))
                else
                    START_TIME=$(grep -E "^${VMID}:" "$STATE_FILE" | cut -d':' -f2)
                    if [ -z "$START_TIME" ]; then
                        log "Guest [$VMID] is idle. Starting idle timer."
                        NEW_STATES="${NEW_STATES}${VMID}:${CURRENT_TIME}
"
                    else
                        ELAPSED=$((CURRENT_TIME - START_TIME))
                        TIMEOUT_SEC=$((TIMEOUT_MIN * 60))
                        log "Guest [$VMID] has been idle for $ELAPSED seconds (Timeout: $TIMEOUT_SEC seconds)."
                        
                        if [ "$ELAPSED" -ge "$TIMEOUT_SEC" ]; then
                            log "Guest [$VMID] idle timeout reached. Preparing to suspend/stop..."
                            ORCHESTRATED_GUESTS_RUNNING=$((ORCHESTRATED_GUESTS_RUNNING - 1))
                            
                            # Resolve friendly name for notifications
                            GUEST_NAME=$(echo "$GUEST_NAME_MAP" | grep -oE "${VMID}:[^,]+" | cut -d':' -f2 2>/dev/null)
                            [ -z "$GUEST_NAME" ] && GUEST_NAME="Guest $VMID"
                            TIMEOUT_MIN="$TIMEOUT_MIN"
                            
                            if [ "$REPORT_ONLY" -eq 1 ]; then
                                log "Guest [$VMID] idle timeout reached (check mode: not suspending)."
                            elif pct status "$VMID" >/dev/null 2>&1; then
                                if [ "$LXC_SUSPEND_METHOD" = "suspend" ]; then
                                    log "Suspending LXC [$VMID]..."
                                    pct suspend "$VMID"
                                    notify "$(render_msg "$MSG_PROXMOX_GUEST_SUSPENDED")"
                                else
                                    log "Stopping LXC [$VMID]..."
                                    pct stop "$VMID"
                                    notify "$(render_msg "$MSG_PROXMOX_GUEST_STOPPED")"
                                fi
                            else
                                if [ "$VM_SUSPEND_METHOD" = "suspend" ]; then
                                    log "Suspending VM [$VMID]..."
                                    qm suspend "$VMID" --todisk 0
                                    notify "$(render_msg "$MSG_PROXMOX_GUEST_SUSPENDED")"
                                else
                                    log "Shutting down VM [$VMID]..."
                                    qm shutdown "$VMID"
                                    notify "$(render_msg "$MSG_PROXMOX_GUEST_STOPPED")"
                                fi
                            fi
                        else
                            NEW_STATES="${NEW_STATES}${VMID}:${START_TIME}
"
                        fi
                    fi
                fi
            else
                log "Guest [$VMID] is active. Resetting idle timer."
            fi
        fi
    done
    
    # In --check mode do not touch the persisted idle timers (a check must have
    # no side effects on the real schedule).
    if [ "$REPORT_ONLY" -eq 0 ]; then
        printf "%s" "$NEW_STATES" | sed '/^$/d' > "$STATE_FILE"
    fi
    
    if [ "$ORCHESTRATED_GUESTS_RUNNING" -gt 0 ]; then
        blocked "orchestrated guest(s) are still active or waiting for idle timeout"
    fi
fi

# 0.5. Check Active Non-Orchestrated / Non-Exempt Running Guests
RUNNING_LXCS_CHECK=$(pct list 2>/dev/null | awk 'NR>1 && $2=="running" {print $1}')
RUNNING_VMS_CHECK=$(qm list 2>/dev/null | awk 'NR>1 && $3=="running" {print $1}')
ALL_RUNNING_GUESTS="$RUNNING_LXCS_CHECK $RUNNING_VMS_CHECK"

BLOCKING_UNMANAGED_GUESTS=""
for g_vmid in $ALL_RUNNING_GUESTS; do
    # Check if guest is in GUEST_ORCHESTRATION_MAP
    is_orchestrated=0
    if [ -n "$GUEST_ORCHESTRATION_MAP" ]; then
        for entry in $(echo "$GUEST_ORCHESTRATION_MAP" | tr ',' ' '); do
            ovmid=$(echo "$entry" | cut -d':' -f1)
            if [ "$g_vmid" = "$ovmid" ]; then
                is_orchestrated=1
                break
            fi
        done
    fi
    
    # Check if guest is exempt (e.g. NAS, Pihole)
    is_exempt=0
    if [ -n "$EXEMPT_SHUTDOWN_GUESTS" ]; then
        for evmid in $(echo "$EXEMPT_SHUTDOWN_GUESTS" | tr ',' ' '); do
            if [ "$g_vmid" = "$evmid" ]; then
                is_exempt=1
                break
            fi
        done
    fi
    
    if [ "$is_orchestrated" -eq 0 ] && [ "$is_exempt" -eq 0 ]; then
        BLOCKING_UNMANAGED_GUESTS="$BLOCKING_UNMANAGED_GUESTS $g_vmid"
    fi
done

if [ -n "$BLOCKING_UNMANAGED_GUESTS" ]; then
    clean_unmanaged=$(echo "$BLOCKING_UNMANAGED_GUESTS" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    blocked "active non-exempt guest(s) are running ($clean_unmanaged)"
fi

# 1. Check Protected Processes
for proc in $PROTECTED_PROCESSES; do
    if pgrep -x "$proc" >/dev/null 2>&1; then
        blocked "protected process '$proc' is currently running"
    fi
done

# 2. Check CPU Load Average
# Read 1-minute load average from /proc/loadavg
LOAD_1=$(awk '{print $1}' /proc/loadavg)

# Multi-core awareness scaling
CORES=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo || echo 1)
ACTUAL_THRESHOLD="$CPU_THRESHOLD"
if [ "$SCALE_CPU_THRESHOLD_BY_CORES" -eq 1 ]; then
    LIMIT_INT=$(to_integer "$CPU_THRESHOLD")
    SCALED_INT=$(( LIMIT_INT * CORES ))
    
    int_part=$(( SCALED_INT / 100 ))
    dec_part=$(( SCALED_INT % 100 ))
    dec_part=$(printf "%02d" "$dec_part")
    ACTUAL_THRESHOLD="${int_part}.${dec_part}"
    log "Multi-core scaling active: CPU Threshold scaled by $CORES cores to $ACTUAL_THRESHOLD"
else
    SCALED_INT=$(to_integer "$CPU_THRESHOLD")
fi

log "Current 1-minute CPU load average: $LOAD_1 (Threshold: $ACTUAL_THRESHOLD)"

LOAD_INT=$(to_integer "$LOAD_1")
if [ "$LOAD_INT" -gt "$SCALED_INT" ]; then
    blocked "CPU load average ($LOAD_1) exceeds threshold ($ACTUAL_THRESHOLD)"
fi

# 2.5. Check Network Interface Traffic Rate (Over 10-second window)
if [ -n "$NET_INTERFACE" ] && [ -d "/sys/class/net/$NET_INTERFACE" ]; then
    # A shorter window in --check mode keeps the bot's pre-flight prompt; the
    # threshold is scaled by the window so the comparison is still in KB/s.
    NET_SAMPLE_SECS=10
    [ "$REPORT_ONLY" -eq 1 ] && NET_SAMPLE_SECS=2

    log "Measuring network throughput on $NET_INTERFACE over $NET_SAMPLE_SECS seconds..."

    RX_BYTES_1=$(cat "/sys/class/net/$NET_INTERFACE/statistics/rx_bytes")
    TX_BYTES_1=$(cat "/sys/class/net/$NET_INTERFACE/statistics/tx_bytes")

    sleep "$NET_SAMPLE_SECS"

    RX_BYTES_2=$(cat "/sys/class/net/$NET_INTERFACE/statistics/rx_bytes")
    TX_BYTES_2=$(cat "/sys/class/net/$NET_INTERFACE/statistics/tx_bytes")

    RX_DIFF=$((RX_BYTES_2 - RX_BYTES_1))
    TX_DIFF=$((TX_BYTES_2 - TX_BYTES_1))

    # Calculate average KB/s
    TOTAL_KB=$(( (RX_DIFF + TX_DIFF) / 1024 ))
    TOTAL_THRESHOLD=$(( NET_THRESHOLD_KBPS * NET_SAMPLE_SECS ))
    AVERAGE_KBPS=$(( TOTAL_KB / NET_SAMPLE_SECS ))

    log "Network activity: ~${AVERAGE_KBPS} KB/s (Threshold: ${NET_THRESHOLD_KBPS} KB/s)"

    if [ "$TOTAL_KB" -gt "$TOTAL_THRESHOLD" ]; then
        blocked "network throughput (~${AVERAGE_KBPS} KB/s) exceeds threshold (${NET_THRESHOLD_KBPS} KB/s)"
    fi
else
    log "Skipping network throughput check (Interface $NET_INTERFACE not found or not configured)."
fi

# 3. Check Network Connections on Monitored Ports
HOST_SSH_PORT="${HOST_SSH_PORT:-${SSH_PORT:-22}}"
ACTIVE_CHECK_PORTS="$MONITORED_PORTS"
if [ -n "$HOST_SSH_PORT" ] && ! echo ",$ACTIVE_CHECK_PORTS," | grep -q ",$HOST_SSH_PORT,"; then
    ACTIVE_CHECK_PORTS="$ACTIVE_CHECK_PORTS,$HOST_SSH_PORT"
fi

for port in $(echo "$ACTIVE_CHECK_PORTS" | tr ',' ' '); do
    port_num=$(echo "$port" | cut -d'/' -f1)
    proto=$(echo "$port" | cut -d'/' -f2 -s)
    [ -z "$proto" ] && proto="tcp"
    
    conn_count=0
    if [ "$proto" = "tcp" ]; then
        # We look for ESTABLISHED TCP connections on the given port
        # Avoid matching local listening sockets or loops
        conn_count=$(ss -t -an state established | grep -c -E ":$port_num[[:space:]]")
    else
        # For UDP, check conntrack if available, else fallback to ss -ua
        if command -v conntrack >/dev/null 2>&1; then
            conn_count=$(conntrack -L -p udp --dport "$port_num" 2>/dev/null | grep -c -E "ESTABLISHED|ASSURED")
        else
            # Native fallback using ss -u -an
            conn_count=$(ss -u -an | grep -c -E ":$port_num[[:space:]]")
        fi
    fi
    
    if [ "$conn_count" -gt 0 ]; then
        blocked "$conn_count active $proto connection(s) on monitored port $port_num"
    fi
done


fi

# --check never acts: report that the action WOULD proceed and stop.
if [ "$REPORT_ONLY" -eq 1 ]; then
    printf 'HOMELAB_CHECK:IDLE\n'
    exit 0
fi

log "CONFIRM: All idle checks passed. Preparing to transition to power-saving mode."

# 4. Gather active guest nodes
RUNNING_LXCS=$(pct list | awk 'NR>1 && $2=="running" {print $1}')
RUNNING_VMS=$(qm list | awk 'NR>1 && $3=="running" {print $1}')

SUSPENDED_LXCS=""
STOPPED_LXCS=""
SUSPENDED_VMS=""
SHUTDOWN_VMS=""

# 5. Suspend/Shutdown Guest Nodes
# Handle LXC Containers
for vmid in $RUNNING_LXCS; do
    if [ "$LXC_SUSPEND_METHOD" = "suspend" ]; then
        log "LXC [$vmid]: Suspending/Freezing container..."
        if pct suspend "$vmid" >/dev/null 2>&1; then
            SUSPENDED_LXCS="$SUSPENDED_LXCS $vmid"
        else
            log "WARNING: Failed to suspend LXC $vmid. Falling back to stop..."
            pct stop "$vmid"
            STOPPED_LXCS="$STOPPED_LXCS $vmid"
        fi
    elif [ "$LXC_SUSPEND_METHOD" = "stop" ]; then
        log "LXC [$vmid]: Stopping container..."
        pct stop "$vmid"
        STOPPED_LXCS="$STOPPED_LXCS $vmid"
    else
        log "LXC [$vmid]: Leaving running (No action)."
    fi
done

# Handle QEMU VMs
for vmid in $RUNNING_VMS; do
    if [ "$VM_SUSPEND_METHOD" = "suspend" ]; then
        log "VM [$vmid]: Suspending/Freezing VM..."
        if qm suspend "$vmid" --todisk 0 >/dev/null 2>&1; then
            SUSPENDED_VMS="$SUSPENDED_VMS $vmid"
        else
            log "WARNING: Failed to suspend VM $vmid. Falling back to shutdown..."
            qm shutdown "$vmid" --timeout 90 >/dev/null 2>&1 &
            SHUTDOWN_VMS="$SHUTDOWN_VMS $vmid"
        fi
    elif [ "$VM_SUSPEND_METHOD" = "shutdown" ]; then
        log "VM [$vmid]: Sending ACPI shutdown signal..."
        # --timeout bounds the otherwise 180s-per-VM default, and '&' shuts the
        # VMs down in parallel: sequentially this could stall a reboot for
        # ~3 minutes per stubborn VM, which looked like "the host never reboots".
        qm shutdown "$vmid" --timeout 90 >/dev/null 2>&1 &
        SHUTDOWN_VMS="$SHUTDOWN_VMS $vmid"
    else
        log "VM [$vmid]: Leaving running (No action)."
    fi
done

# Wait for stopped/shutdown nodes to fully power down with timeout
if [ -n "$STOPPED_LXCS" ] || [ -n "$SHUTDOWN_VMS" ]; then
    log "Waiting for guest nodes to power off completely..."
    for i in $(seq 1 20); do
        ACTIVE_COUNT=0
        for vmid in $STOPPED_LXCS $SHUTDOWN_VMS; do
            if qm status "$vmid" >/dev/null 2>&1 && [ "$(qm status "$vmid" | awk '{print $2}')" = "running" ]; then
                ACTIVE_COUNT=$((ACTIVE_COUNT + 1))
            elif pct status "$vmid" >/dev/null 2>&1 && [ "$(pct status "$vmid" | awk '{print $2}')" = "running" ]; then
                ACTIVE_COUNT=$((ACTIVE_COUNT + 1))
            fi
        done
        if [ "$ACTIVE_COUNT" -eq 0 ]; then
            log "All guest nodes stopped cleanly."
            break
        fi
        sleep 5
    done
fi

# 6. Put Proxmox Host to Sleep (ACPI S3 State), Shutdown or Reboot
if [ "$ACTION" = "shutdown" ]; then
    log "Shutdown: Powering off Proxmox host..."
    notify "[Proxmox Host Shutting Down] System is powering off cleanly!"
    sync
    wait
    sleep 3
    shutdown -h now
    exit 0
elif [ "$ACTION" = "reboot" ]; then
    log "Reboot: Rebooting Proxmox host..."
    notify "[Proxmox Host Rebooting] System is rebooting cleanly!"
    sync
    wait
    sleep 3
    reboot
    exit 0
else
    log "Zzz: Suspending Proxmox host to RAM (ACPI S3)..."
    sync
    wait
    sleep 3
    systemctl suspend
fi

# =============================================================================
# === THE HOST IS NOW ASLEEP. EXECUTION STOPS HERE UNTIL SYSTEM WAKES UP. ===
# =============================================================================

# --- WAKE UP SEQUENCE ---
log "WAKE: Proxmox host has woken up from S3 suspend."
rm -f /tmp/proxmox_guest_idle_states 2>/dev/null

# 7. Resume Suspended Nodes
# Resume QEMU VMs first (often takes a bit longer to reactivate)
for vmid in $SUSPENDED_VMS; do
    log "VM [$vmid]: Resuming VM from suspended state..."
    qm resume "$vmid" >/dev/null 2>&1
done

# Resume LXC Containers
for vmid in $SUSPENDED_LXCS; do
    log "LXC [$vmid]: Resuming container from frozen state..."
    pct resume "$vmid" >/dev/null 2>&1
done

# Start stopped/shutdown nodes
# Proxmox does not run boot sequence on S3 wake, so we manually start them
# if they were running when this script suspended the host or if onboot is enabled
for vmid in $STOPPED_LXCS; do
    log "LXC [$vmid]: Restarting container (restoring pre-sleep state)..."
    pct start "$vmid" >/dev/null 2>&1 || true
done

for vmid in $SHUTDOWN_VMS; do
    log "VM [$vmid]: Restarting VM (restoring pre-sleep state)..."
    qm start "$vmid" >/dev/null 2>&1 || true
done

log "WAKE: All guest nodes successfully restored. Power-saving cycle complete."
exit 0
