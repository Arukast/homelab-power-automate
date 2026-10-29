#!/bin/sh
# =============================================================================
# OpenWrt Telegram Bot Command Processor
# File: /usr/bin/telegram_components/process_command_helper.sh
# =============================================================================

# -----------------------------------------------------------------------------
# Command dispatch table:  "<command>|<handler>|<pass_arg1>"
#   <command>   : slash command name without the leading '/'
#   <handler>   : handler function to invoke
#   <pass_arg1> : 1 → call handler with (chat_id, msg_id, arg1); 0 → (chat_id, msg_id)
# Multi-argument commands (/start, /node, /maintenance) and the bare-/start
# "begin" case are handled explicitly in process_command() below.
# -----------------------------------------------------------------------------
CMD_DISPATCH_TABLE='
help|help_command|0
status|status_command|0
wake|wake_command|0
wake_proxmox|wake_command|0
sleep|sleep_command|0
sleepforce|sleepforce_command|0
hostshutdown|hostshutdown_command|0
hostshutdownforce|hostshutdownforce_command|0
hostreboot|hostreboot_command|0
hostrebootforce|hostrebootforce_command|0
list|list_command|0
stop|stop_command|1
restart|restart_command|1
'

# Main Command Processor
process_command() {
    local cmd="$1"
    local chat_id="$2"
    local msg_id="$3"

    # Extract action and first argument
    local action_raw
    action_raw=$(echo "$cmd" | awk '{print $1}')
    # Strip bot username suffix if present (e.g., /status@MyBot -> /status)
    local action
    action=$(echo "$action_raw" | cut -d'@' -f1 | tr 'A-Z' 'a-z')
    local arg1
    arg1=$(echo "$cmd" | awk '{print $2}')

    # Commands that need special (multi-argument / bare) handling.
    case "$action" in
        /maintenance)
            # /maintenance [sub] [args...]
            # NOTE: do NOT use `cut -d' ' -f2-` here: cut returns the WHOLE line
            # when the delimiter is absent, so a bare /maintenance looked like the
            # sub-command "/maintenance". sed strips the leading command word and
            # yields an empty string for a bare invocation.
            local full_cmd msub mrest
            full_cmd=$(printf '%s' "$cmd" | sed 's/^[^[:space:]]*[[:space:]]*//')
            if [ -z "$full_cmd" ]; then
                maintenance_command "$chat_id" "$msg_id"
            else
                # Split the sub-command from the (possibly multi-word) remainder,
                # which is passed as ONE argument so reasons keep their spaces.
                msub="${full_cmd%% *}"
                if [ "$msub" = "$full_cmd" ]; then
                    mrest=""
                else
                    mrest="${full_cmd#* }"
                fi
                maintenance_command "$chat_id" "$msg_id" "$msub" "$mrest"
            fi
            return
            ;;

        /node)
            # /node <vm|ct> <vmid> <start|stop|restart>
            # node_command signature: (chat_id, message_id, operation, type, vmid)
            local node_type node_vmid node_op
            node_type=$(echo "$cmd" | awk '{print $2}')
            node_vmid=$(echo "$cmd" | awk '{print $3}')
            node_op=$(echo "$cmd" | awk '{print $4}')
            node_command "$chat_id" "$msg_id" "$node_op" "$node_type" "$node_vmid"
            return
            ;;

        /start)
            # Bare /start is Telegram's conventional "begin" command → show help.
            # /start <vmid> starts a guest (VM vs LXC auto-detected from the VMID).
            if [ -z "$arg1" ]; then
                help_command "$chat_id" "$msg_id"
            else
                start_command "$chat_id" "$msg_id" "$arg1"
            fi
            return
            ;;
    esac

    # Single-argument / no-argument commands: look the handler up in the table.
    local name entry
    name=$(echo "$action" | cut -c2-)
    entry=$(printf '%s\n' "$CMD_DISPATCH_TABLE" | grep "^${name}|" | head -n 1)

    if [ -n "$entry" ]; then
        local rest handler pass_arg
        rest="${entry#*|}"
        handler="${rest%%|*}"
        pass_arg="${rest##*|}"
        if [ "$pass_arg" = "1" ]; then
            $handler "$chat_id" "$msg_id" "$arg1"
        else
            $handler "$chat_id" "$msg_id"
        fi
        return
    fi

    send_message "$chat_id" "$MSG_BOT_UNKNOWN_COMMAND"
}

# Action Processor for callback-based structured data (cmd:type:id:op).
# Only reachable from inline-keyboard callbacks, which the bot no longer sends;
# kept so that keyboards still present in older chat history keep working.
process_action() {
    local action_data="$1"
    local chat_id="$2"
    local msg_id="$3"

    local action_type=$(echo "$action_data" | cut -d':' -f1)

    case "$action_type" in
        cmd)
            local cmd_name=$(echo "$action_data" | cut -d':' -f2)
            local target=$(echo "$action_data" | cut -d':' -f3)
            local op=$(echo "$action_data" | cut -d':' -f4)

            case "$cmd_name" in
                status|list|wake|sleep|sleepforce|hostshutdown|hostshutdownforce|hostreboot|hostrebootforce|maintenance)
                    process_command "/$cmd_name" "$chat_id" "$msg_id"
                    ;;
                vm|ct)
                    local gtool
                    if [ "$cmd_name" = "vm" ]; then gtool="qm"; else gtool="pct"; fi
                    case "$op" in
                        start)   guest_action "$chat_id" "$msg_id" "$target" "$gtool" start ;;
                        stop)    guest_action "$chat_id" "$msg_id" "$target" "$gtool" stop ;;
                        restart) guest_action "$chat_id" "$msg_id" "$target" "$gtool" reboot ;;
                        *)       send_message "$chat_id" "Invalid guest operation: $op" ;;
                    esac
                    ;;
                *)
                    send_message "$chat_id" "Unknown command: $cmd_name"
                    ;;
            esac
            ;;
        maint)
            local sub_type=$(echo "$action_data" | cut -d':' -f2)
            local a3=$(echo "$action_data" | cut -d':' -f3)
            local a4=$(echo "$action_data" | cut -d':' -f4)

            if [ "$sub_type" = "sys" ]; then
                process_command "/maintenance system $a3" "$chat_id" "$msg_id"
            elif [ "$sub_type" = "service" ]; then
                process_command "/maintenance service $a3 $a4" "$chat_id" "$msg_id"
            fi
            ;;
        *)
            send_message "$chat_id" "Invalid action format."
            ;;
    esac
}
