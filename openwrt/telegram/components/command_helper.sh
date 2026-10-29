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

# Common: check for blocking guests (VMs/containers) during shutdown/reboot
# Sets blocking_guests variable if guests found; returns 1 if blocking, 0 otherwise
cmd_blocking_guests_check() {
    local chat_id="$1"
    local message_id="$2"
    local running_guests="$($SSH_CMD "pct list | awk 'NR>1 && \$2==\"running\" {print \$1}'; qm list | awk 'NR>1 && \$3==\"running\" {print \$1}'" 2>/dev/null)"
    local blocking_guests=""

    if [ -n "$running_guests" ]; then
        for vmid in $running_guests; do
            local is_exempt=0
            for exempt in $(echo "$EXEMPT_SHUTDOWN_GUESTS" | tr ',' ' '); do
                if [ "$vmid" = "$exempt" ]; then
                    is_exempt=1
                    break
                fi
            done
            if [ "$is_exempt" -eq 0 ]; then
                blocking_guests="$blocking_guests $vmid"
            fi
        done
    fi

    if [ -n "$blocking_guests" ]; then
        local clean_blocking=$(echo "$blocking_guests" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        send_message "$chat_id" "*Shutdown Blocked:* Core power actions are blocked because active non-exempt guest(s) are running: *${clean_blocking}*.

Please stop them first, or use \`/hostshutdownforce\`." "" "$message_id"
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

# Ensure system is UNDER maintenance before allowing an action
cmd_require_maintenance() {
    local chat_id="$1"
    local message_id="$2"
    local cmd_str="$3"

    if [ ! -f "/etc/homelab_maintenance/system" ]; then
        send_message "$chat_id" "⚠️ *Action Blocked:* The host is currently in its *Active Window*.
Core power actions are prohibited to prevent accidental downtime.

Please enable maintenance mode first, or use the \`force\` version of this command (e.g., \`$cmd_str'force\`)." "" "$message_id"
        return 1
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

# =============================================================================
# Unified Guest Lifecycle Action
#   guest_action <chat_id> <message_id> <vmid> <pct|qm> <start|stop|reboot>
#
# Collapses the six guest-lifecycle commands (/ctstart /ctstop /ctrestart
# /vmstart /vmstop /vmrestart) into a single implementation.
#   pct → LXC container, qm → QEMU virtual machine
# The command-specific message keys and the maintenance/usage guards are
# selected from <tool>:<op> so each command keeps its original wording.
# =============================================================================
guest_action() {
    local chat_id="$1"
    local message_id="$2"
    local vmid="$3"
    local tool="$4"
    local op="$5"

    local usage msg_progress msg_not_found msg_success msg_failed command_str
    case "${tool}:${op}" in
        pct:start)
            usage="$MSG_BOT_CT_START_USAGE"
            msg_progress="$MSG_BOT_CT_START_STARTING"
            msg_not_found="$MSG_BOT_CT_START_NOT_FOUND"
            msg_success="$MSG_BOT_CT_START_SUCCESS"
            msg_failed="$MSG_BOT_CT_START_FAILED"
            command_str="/ctstart $vmid"
            ;;
        pct:stop)
            usage="$MSG_BOT_CT_STOP_USAGE"
            msg_progress="$MSG_BOT_CT_STOP_STOPPING"
            msg_not_found="$MSG_BOT_CT_STOP_NOT_FOUND"
            msg_success="$MSG_BOT_CT_STOP_SUCCESS"
            msg_failed="$MSG_BOT_CT_STOP_FAILED"
            command_str="/ctstop $vmid"
            ;;
        pct:reboot)
            usage="$MSG_BOT_CT_RESTART_USAGE"
            msg_progress="$MSG_BOT_CT_RESTART_RESTARTING"
            msg_not_found="$MSG_BOT_CT_RESTART_NOT_FOUND"
            msg_success="$MSG_BOT_CT_RESTART_SUCCESS"
            msg_failed="$MSG_BOT_CT_RESTART_FAILED"
            command_str="/ctrestart $vmid"
            ;;
        qm:start)
            usage="$MSG_BOT_VM_START_USAGE"
            msg_progress="$MSG_BOT_VM_START_SENDING"
            msg_not_found="$MSG_BOT_VM_START_NOT_FOUND"
            msg_success="$MSG_BOT_VM_START_SUCCESS"
            msg_failed="$MSG_BOT_VM_START_FAILED"
            command_str="/vmstart $vmid"
            ;;
        qm:stop)
            usage="$MSG_BOT_VM_STOP_USAGE"
            msg_progress="$MSG_BOT_VM_STOP_SENDING"
            msg_not_found="$MSG_BOT_VM_STOP_NOT_FOUND"
            msg_success="$MSG_BOT_VM_STOP_SUCCESS"
            msg_failed="$MSG_BOT_VM_STOP_FAILED"
            command_str="/vmstop $vmid"
            ;;
        qm:reboot)
            usage="$MSG_BOT_VM_RESTART_USAGE"
            msg_progress="$MSG_BOT_VM_RESTART_SENDING"
            msg_not_found="$MSG_BOT_VM_RESTART_NOT_FOUND"
            msg_success="$MSG_BOT_VM_RESTART_SUCCESS"
            msg_failed="$MSG_BOT_VM_RESTART_FAILED"
            command_str="/vmrestart $vmid"
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
        # QEMU start announces in the foreground immediately; the LXC start path
        # runs entirely in the worker (it may have to wake the host first), so
        # its "starting" notice is emitted from inside the worker.
        if [ "$tool" = "qm" ]; then
            send_message "$chat_id" "$msg_progress" "" "$message_id"
        fi

        (
            # Re-establish scope for the subshell
            chat_id="$chat_id"
            message_id="$message_id"

            if [ "$tool" = "pct" ]; then
                if ! is_host_alive; then
                    send_message "$chat_id" "$MSG_BOT_CT_START_HOST_WAKING" "" "$message_id"
                    etherwake -i "${LAN_INTERFACE:-br-lan}" "$HOST_MAC"

                    send_message "$chat_id" "$MSG_BOT_CT_START_WAITING" "" "$message_id"

                    local success=0
                    local attempt=1
                    while [ $attempt -le 25 ]; do
                        if is_host_alive; then
                            if $SSH_CMD "echo OK" >/dev/null 2>&1; then
                                success=1
                                break
                            fi
                        fi
                        sleep 3
                        attempt=$((attempt + 1))
                    done

                    if [ $success -eq 0 ]; then
                        send_message "$chat_id" "$MSG_BOT_CT_START_TIMEOUT" "" "$message_id"
                        return
                    fi

                    send_message "$chat_id" "$MSG_BOT_CT_START_HOST_ONLINE" "" "$message_id"
                fi
                send_message "$chat_id" "$msg_progress" "" "$message_id"
            fi

            if ! $SSH_CMD "$tool status $vmid" >/dev/null 2>&1; then
                send_message "$chat_id" "$msg_not_found" "" "$message_id"
                return
            fi

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
                if [ "$tool" = "qm" ]; then
                    export arg2="$display_out"
                    send_message "$chat_id" "$msg_success" "" "$message_id"
                else
                    send_message "$chat_id" "$(expand_msg "$msg_success")
\`\`\`
$display_out
\`\`\`" "" "$message_id"
                fi
            fi
        ) >/dev/null 2>&1 </dev/null &
    else
        # stop / restart — handled synchronously after confirming the host is up
        if ! is_host_alive; then
            send_message "$chat_id" "$MSG_HOST_OFFLINE" "" "$message_id"
            return
        fi

        send_message "$chat_id" "$msg_progress" "" "$message_id"

        if ! $SSH_CMD "$tool status $vmid" >/dev/null 2>&1; then
            send_message "$chat_id" "$msg_not_found" "" "$message_id"
            return
        fi

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
            if [ "$tool" = "qm" ]; then
                export arg2="$payload"
                send_message "$chat_id" "$msg_success" "" "$message_id"
            else
                send_message "$chat_id" "$(expand_msg "$msg_success")
\`\`\`
$payload
\`\`\`" "" "$message_id"
            fi
        fi
    fi
}

# =============================================================================
# Unified Host Power Action
#   host_power_action <chat_id> <message_id> <action>
#     action ∈ sleep | sleepforce | shutdown | shutdownforce | reboot | rebootforce
#
# Collapses the six host-power commands into a single implementation while
# preserving each command's original guards (aliveness, maintenance window,
# blocking guests), target-state marker and remote invocation.
# =============================================================================
host_power_action() {
    local chat_id="$1"
    local message_id="$2"
    local action="$3"

    local progress_msg state remote_args done_msg maint_cmd
    local alive_style="check"    # check | inline | silent
    local maint_check="none"     # active | require | none
    local block_guests=0

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
            maint_check="active"
            maint_cmd="/sleepforce"
            ;;
        shutdown)
            progress_msg="$MSG_BOT_SHUTDOWN_SENDING"
            state="SHUTDOWN"
            remote_args="--shutdown"
            done_msg="$MSG_BOT_SHUTDOWN_EXECUTED"
            alive_style="check"
            maint_check="require"
            maint_cmd="/hostshutdown"
            block_guests=1
            ;;
        shutdownforce)
            progress_msg="$MSG_BOT_SHUTDOWN_FORCE_SENDING"
            state="SHUTDOWN"
            remote_args="--shutdown --force"
            done_msg="$MSG_BOT_SHUTDOWN_EXECUTED"
            alive_style="inline"
            maint_check="none"
            ;;
        reboot)
            progress_msg="$MSG_BOT_REBOOT_SENDING"
            state="REBOOT"
            remote_args="--reboot"
            done_msg="$MSG_BOT_REBOOT_EXECUTED"
            alive_style="silent"
            maint_check="require"
            maint_cmd="/hostreboot"
            block_guests=1
            ;;
        rebootforce)
            progress_msg="$MSG_BOT_REBOOT_FORCE_SENDING"
            state="REBOOT"
            remote_args="--reboot --force"
            done_msg="$MSG_BOT_REBOOT_EXECUTED"
            alive_style="inline"
            maint_check="active"
            maint_cmd="/hostrebootforce"
            ;;
        *)
            return
            ;;
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

    case "$maint_check" in
        active)
            if ! cmd_check_maintenance_active "$chat_id" "$message_id" "$maint_cmd"; then return; fi
            ;;
        require)
            if ! cmd_require_maintenance "$chat_id" "$message_id" "$maint_cmd"; then return; fi
            ;;
    esac

    if [ "$block_guests" -eq 1 ]; then
        if ! cmd_blocking_guests_check "$chat_id" "$message_id"; then return; fi
    fi

    send_message "$chat_id" "$progress_msg" "" "$message_id"
    echo "$state" > /tmp/homelab_target_state
    # remote_args is appended without a stray space so the exact command string
    # still matches the Proxmox SSH wrapper allow-list.
    $SSH_CMD "nohup /usr/local/bin/proxmox_idle_monitor.sh${remote_args:+ $remote_args} >/dev/null 2>&1 &" 2>/dev/null
    send_message "$chat_id" "$done_msg" "" "$message_id"
}
