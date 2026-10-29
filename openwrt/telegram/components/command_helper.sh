#!/bin/sh
# =============================================================================
# OpenWrt Telegram Bot Command Helper
# Shared utilities for Telegram command handlers
# File: /usr/bin/telegram_components/command_helper.sh
# =============================================================================

# Common: check host aliveness and send appropriate offline message
cmd_check_host_alive() {
    local chat_id="$1"
    local message_id="$2"
    if ! is_host_alive; then
        send_message "$chat_id" "$MSG_HOST_OFFLINE" "" "$message_id"
        return 1
    fi
    return 0
}

# Check if system or specific service is under maintenance
cmd_check_maintenance_active() {
    local chat_id="$1"
    local message_id="$2"
    local cmd_str="$3"
    local target_id="$4"

    # Check System Maintenance
    if [ -f "/etc/homelab_maintenance/system" ]; then
        local reason=$(cat "/etc/homelab_maintenance/system")
        send_message "$chat_id" "⚠️ *Action Blocked:* System-wide maintenance is ACTIVE.
Reason: _${reason}_
Command \`$cmd_str\` is prohibited." "" "$message_id"
        return 1
    fi

    # Check Service Maintenance
    if [ -n "$target_id" ]; then
        if [ -f "/etc/homelab_maintenance/service_${target_id}" ]; then
            local reason=$(cat "/etc/homelab_maintenance/service_${target_id}")
            send_message "$chat_id" "⚠️ *Action Blocked:* Service *${target_id}* is under maintenance.
Reason: _${reason}_
Command \`$cmd_str\` is prohibited." "" "$message_id"
            return 1
        fi
    fi

    return 0
}

validate_numeric_arg() {
    local chat_id="$1"
    local val="$2"
    local label="$3"
    local message_id="$4"

    if ! echo "$val" | grep -qE "^[0-9]+$"; then
        send_message "$chat_id" "Error: $label must be numeric." "" "$message_id"
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# _guest_probe <pct|qm|auto> <vmid>
# Echoes "<tool> <state>" for the guest (e.g. "qm running"), or nothing if the
# guest does not exist for the requested tool. With "auto" the type is derived
# from the VMID (Proxmox VMIDs are unique across VMs and containers).
# ---------------------------------------------------------------------------
_guest_probe() {
    local tool="$1"
    local vmid="$2"
    local out="" t=""

    if [ "$tool" = "pct" ] || [ "$tool" = "qm" ]; then
        out=$($SSH_CMD "$tool status $vmid" 2>/dev/null)
        [ -n "$out" ] && t="$tool"
    else
        out=$($SSH_CMD "pct status $vmid" 2>/dev/null)
        if [ -n "$out" ]; then
            t="pct"
        else
            out=$($SSH_CMD "qm status $vmid" 2>/dev/null)
            [ -n "$out" ] && t="qm"
        fi
    fi

    [ -z "$t" ] && return 1
    printf '%s %s\n' "$t" "$(printf '%s\n' "$out" | awk '{print $2}')"
    return 0
}

# ---------------------------------------------------------------------------
# _guest_require <chat_id> <message_id> <vmid> <pct|qm|auto> <not_found_msg>
# Echoes "<tool> <state>" when the guest exists. Otherwise it sends the
# appropriate reply (a type-mismatch hint when the VMID exists as the *other*
# type, else <not_found_msg>) and returns 1.
# ---------------------------------------------------------------------------
_guest_require() {
    local chat_id="$1"
    local message_id="$2"
    local vmid="$3"
    local tool="$4"
    local not_found_msg="$5"

    local probe
    probe=$(_guest_probe "$tool" "$vmid")

    if [ -z "$probe" ]; then
        if [ "$tool" = "pct" ] || [ "$tool" = "qm" ]; then
            local other requested actual
            if [ "$tool" = "qm" ]; then
                other="pct"; requested="VM"; actual="CT"
            else
                other="qm"; requested="CT"; actual="VM"
            fi
            if [ -n "$(_guest_probe "$other" "$vmid")" ]; then
                export arg1="$vmid"; export arg2="$actual"; export arg3="$requested"
                send_message "$chat_id" "$(render_msg "$MSG_BOT_GUEST_WRONG_TYPE")" "" "$message_id"
                return 1
            fi
        fi
        send_message "$chat_id" "$not_found_msg" "" "$message_id"
        return 1
    fi

    printf '%s\n' "$probe"
    return 0
}

# =============================================================================
# Unified Guest Lifecycle Action
#   guest_action <chat_id> <message_id> <vmid> <pct|qm|auto> <start|stop|reboot>
#
# The single implementation behind /start /stop /restart and /node.
#   auto → resolve the guest type from the VMID. Proxmox VMIDs are unique across
#          QEMU VMs and LXC containers, so the type is always derivable.
#   pct  → force an LXC container (used by /node ct ...)
#   qm   → force a QEMU VM       (used by /node vm ...)
# =============================================================================
guest_action() {
    local chat_id="$1"
    local message_id="$2"
    local vmid="$3"
    local tool="$4"
    local op="$5"

    local usage msg_progress msg_not_found msg_success msg_failed msg_already_running command_str
    case "$op" in
        start)
            usage="$MSG_BOT_GUEST_START_USAGE"
            msg_progress="$MSG_BOT_GUEST_STARTING"
            msg_not_found="$MSG_BOT_GUEST_NOT_FOUND"
            msg_success="$MSG_BOT_GUEST_START_SUCCESS"
            msg_failed="$MSG_BOT_GUEST_START_FAILED"
            msg_already_running="$MSG_BOT_GUEST_ALREADY_RUNNING"
            command_str="/start $vmid"
            ;;
        stop)
            usage="$MSG_BOT_GUEST_STOP_USAGE"
            msg_progress="$MSG_BOT_GUEST_STOPPING"
            msg_not_found="$MSG_BOT_GUEST_NOT_FOUND"
            msg_success="$MSG_BOT_GUEST_STOP_SUCCESS"
            msg_failed="$MSG_BOT_GUEST_STOP_FAILED"
            command_str="/stop $vmid"
            ;;
        reboot)
            usage="$MSG_BOT_GUEST_RESTART_USAGE"
            msg_progress="$MSG_BOT_GUEST_RESTARTING"
            msg_not_found="$MSG_BOT_GUEST_NOT_FOUND"
            msg_success="$MSG_BOT_GUEST_RESTART_SUCCESS"
            msg_failed="$MSG_BOT_GUEST_RESTART_FAILED"
            command_str="/restart $vmid"
            ;;
        *)
            return
            ;;
    esac

    if [ -z "$vmid" ]; then
        send_message "$chat_id" "$usage" "" "$message_id"
        return
    fi

    if ! validate_numeric_arg "$chat_id" "$vmid" "VMID" "$message_id"; then return; fi
    if ! cmd_check_maintenance_active "$chat_id" "$message_id" "$command_str"; then return; fi

    # Every guest message template references $arg1 as the VMID
    export arg1="$vmid"

    if [ "$op" = "start" ]; then
        # Runs in a worker: it may have to wake the host before it can even
        # discover the guest type. The "starting" notice is emitted only once we
        # know the guest exists and is not already running.
        (
            # Re-establish scope for the subshell
            chat_id="$chat_id"
            message_id="$message_id"

            # Wake the host if needed.
            if ! is_host_alive; then
                send_message "$chat_id" "$MSG_BOT_GUEST_HOST_WAKING" "" "$message_id"
                etherwake -i "${LAN_INTERFACE:-br-lan}" "$HOST_MAC"
                send_message "$chat_id" "$MSG_BOT_GUEST_WAITING" "" "$message_id"

                local success=0
                local attempt=1
                while [ $attempt -le 25 ]; do
                    if is_host_alive && $SSH_CMD "echo OK" >/dev/null 2>&1; then
                        success=1
                        break
                    fi
                    sleep 3
                    attempt=$((attempt + 1))
                done

                if [ $success -eq 0 ]; then
                    send_message "$chat_id" "$MSG_BOT_GUEST_TIMEOUT" "" "$message_id"
                    return
                fi

                send_message "$chat_id" "$MSG_BOT_GUEST_HOST_ONLINE" "" "$message_id"
            fi

            # Resolve the guest type + state (or report not-found / wrong type).
            local probe
            probe=$(_guest_require "$chat_id" "$message_id" "$vmid" "$tool" "$msg_not_found") || return
            tool="${probe%% *}"

            # Already running? Report it instead of issuing a start.
            if [ "${probe##* }" = "running" ]; then
                send_message "$chat_id" "$msg_already_running" "" "$message_id"
                return
            fi

            send_message "$chat_id" "$msg_progress" "" "$message_id"

            local start_out
            start_out=$($SSH_CMD "$tool start $vmid" 2>&1)
            local ret=$?
            local clean_out
            clean_out=$(echo "$start_out" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

            if [ $ret -ne 0 ]; then
                export arg2="${clean_out:-Command failed with exit code $ret}"
                send_message "$chat_id" "$msg_failed" "" "$message_id"
            else
                local display_out
                display_out=$(echo "$clean_out" | grep -vE "failed to reset PCI device|error writing '1' to '/sys/bus/pci/devices/.*reset'|swtpm_setup:" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
                if [ -z "$display_out" ]; then
                    display_out="Started successfully"
                fi
                export arg2="$display_out"
                send_message "$chat_id" "$msg_success" "" "$message_id"
            fi
        ) >/dev/null 2>&1 </dev/null &
    else
        # stop / restart — synchronous, requires a reachable host
        if ! is_host_alive; then
            send_message "$chat_id" "$MSG_HOST_OFFLINE" "" "$message_id"
            return
        fi

        # Resolve the guest type + state (or report not-found / wrong type).
        local probe
        probe=$(_guest_require "$chat_id" "$message_id" "$vmid" "$tool" "$msg_not_found") || return
        tool="${probe%% *}"

        send_message "$chat_id" "$msg_progress" "" "$message_id"

        local res_out
        res_out=$($SSH_CMD "$tool $op $vmid" 2>&1)
        local ret=$?
        local clean_res
        clean_res=$(echo "$res_out" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

        if [ $ret -ne 0 ]; then
            export arg2="${clean_res:-Command failed with exit code $ret}"
            send_message "$chat_id" "$msg_failed" "" "$message_id"
        else
            local payload="$clean_res"
            if [ -z "$payload" ]; then
                case "$op" in
                    stop) payload="Stop signal dispatched" ;;
                    reboot) payload="Restart signal dispatched" ;;
                esac
            fi
            export arg2="$payload"
            send_message "$chat_id" "$msg_success" "" "$message_id"
        fi
    fi
}

# =============================================================================
# Unified Host Power Action
#   host_power_action <chat_id> <message_id> <action>
#     action ∈ sleep | sleepforce | shutdown | shutdownforce | reboot | rebootforce
#
# Collapses the six host-power commands into a single implementation with ONE
# uniform gating rule, so /sleep, /hostshutdown and /hostreboot behave the same:
#   * force variants      → bypass all safety/idle criteria
#   * safe variants       → refused while maintenance mode is ON, and refused
#                           when the host's idle check (--check) declines
#                           (active window, running guests, CPU, network, ports)
# =============================================================================
host_power_action() {
    local chat_id="$1"
    local message_id="$2"
    local action="$3"

    local progress_msg state remote_args done_msg maint_cmd
    local alive_style="check"    # check | inline | silent
    local maint_check="none"     # active | none
    local precheck=0

    # The force variants deliberately carry no maint_check and no precheck: they
    # bypass all safety/idle criteria (see README). The safe variants are gated
    # by maintenance mode (router-side) and by the host's idle check (--check).
    case "$action" in
        sleep)
            progress_msg="$MSG_BOT_SLEEP_TRIGGERED"
            state="SLEEP"
            remote_args=""
            done_msg="$MSG_BOT_SLEEP_EXECUTED"
            alive_style="check"
            maint_check="active"
            maint_cmd="/sleep"
            ;;
        sleepforce)
            progress_msg="$MSG_BOT_SLEEP_FORCE_TRIGGERED"
            state="SLEEP"
            remote_args="--force"
            done_msg="$MSG_BOT_SLEEP_EXECUTED"
            alive_style="check"
            maint_cmd="/sleepforce"
            ;;
        shutdown)
            progress_msg="$MSG_BOT_SHUTDOWN_SENDING"
            state="SHUTDOWN"
            remote_args="--shutdown"
            done_msg="$MSG_BOT_SHUTDOWN_EXECUTED"
            alive_style="check"
            maint_check="active"
            maint_cmd="/hostshutdown"
            ;;
        shutdownforce)
            progress_msg="$MSG_BOT_SHUTDOWN_FORCE_SENDING"
            state="SHUTDOWN"
            remote_args="--shutdown --force"
            done_msg="$MSG_BOT_SHUTDOWN_EXECUTED"
            alive_style="inline"
            maint_cmd="/hostshutdownforce"
            ;;
        reboot)
            progress_msg="$MSG_BOT_REBOOT_SENDING"
            state="REBOOT"
            remote_args="--reboot"
            done_msg="$MSG_BOT_REBOOT_EXECUTED"
            alive_style="silent"
            maint_check="active"
            maint_cmd="/hostreboot"
            ;;
        rebootforce)
            progress_msg="$MSG_BOT_REBOOT_FORCE_SENDING"
            state="REBOOT"
            remote_args="--reboot --force"
            done_msg="$MSG_BOT_REBOOT_EXECUTED"
            alive_style="inline"
            maint_cmd="/hostrebootforce"
            ;;
        *)
            return
            ;;
    esac

    # The "safe" variants (not the force ones) are gated by the host's idle
    # checks; ask the host up-front so a refusal can be explained to the user.
    case "$action" in
        sleep|shutdown|reboot) precheck=1 ;;
    esac

    case "$alive_style" in
        check)
            if ! cmd_check_host_alive "$chat_id" "$message_id"; then return; fi
            ;;
        inline)
            if ! is_host_alive; then
                send_message "$chat_id" "$MSG_HOST_OFFLINE" "" "$message_id"
                return
            fi
            ;;
        silent)
            if ! is_host_alive; then return; fi
            ;;
    esac

    # Maintenance mode is a global "hands off" switch: while it is ON, the safe
    # variants are refused (the force variants bypass it, as documented).
    case "$maint_check" in
        active)
            if ! cmd_check_maintenance_active "$chat_id" "$message_id" "$maint_cmd"; then return; fi
            ;;
    esac

    # Pre-flight. The real action runs detached, so without this the user would
    # always see "executed" even when the host refused to act. The host's idle
    # checks (active window, running guests, CPU, network, ports) apply equally to
    # /sleep, /hostshutdown and /hostreboot, so all three report the same way.
    #
    # Probe the host once. The safe variants act on the full verdict; the force
    # variants ignore the safety blocks (that is the point of "force") but still
    # honour the run lock — so a busy host is reported instead of silently
    # no-op'ing like it used to.
    #
    # stderr is captured too: the SSH wrapper reports a refusal ("Access Denied")
    # on stderr, which is how we tell a stale wrapper from a stale monitor.
    local chk verdict
    chk=$($SSH_CMD "/usr/local/bin/proxmox_idle_monitor.sh --check" 2>&1)
    verdict=$(printf '%s\n' "$chk" | grep '^HOMELAB_CHECK:' | tail -n 1)
    export arg1="$maint_cmd"

    case "$verdict" in
        HOMELAB_CHECK:BUSY)
            send_message "$chat_id" "$(render_msg "$MSG_BOT_PRECHECK_BUSY")" "" "$message_id"
            return
            ;;
    esac

    if [ "$precheck" -eq 1 ]; then
        case "$verdict" in
            HOMELAB_CHECK:BLOCKED:*)
                export arg2="${verdict#HOMELAB_CHECK:BLOCKED: }"
                export arg3="${maint_cmd}force"
                send_message "$chat_id" "$(render_msg "$MSG_BOT_ACTION_BLOCKED")" "" "$message_id"
                return
                ;;
            HOMELAB_CHECK:IDLE)
                # Host is idle — fall through and perform the action.
                ;;
            HOMELAB_CHECK:UNSUPPORTED)
                send_message "$chat_id" "$(render_msg "$MSG_BOT_PRECHECK_UNSUPPORTED")" "" "$message_id"
                ;;
            *)
                # No verdict. Distinguish a wrapper refusal from a generic failure
                # so the user knows which side needs redeploying. The action itself
                # is still gated on the host, so this is a warning, not a failure.
                if printf '%s\n' "$chk" | grep -qi 'Access Denied'; then
                    send_message "$chat_id" "$(render_msg "$MSG_BOT_PRECHECK_DENIED")" "" "$message_id"
                else
                    send_message "$chat_id" "$(render_msg "$MSG_BOT_PRECHECK_UNAVAILABLE")" "" "$message_id"
                fi
                ;;
        esac
    fi

    send_message "$chat_id" "$progress_msg" "" "$message_id"
    echo "$state" > /tmp/homelab_target_state
    # remote_args is appended without a stray space so the exact command string
    # still matches the Proxmox SSH wrapper allow-list.
    $SSH_CMD "nohup /usr/local/bin/proxmox_idle_monitor.sh${remote_args:+ $remote_args} >/dev/null 2>&1 &" 2>/dev/null
    send_message "$chat_id" "$done_msg" "" "$message_id"
}
