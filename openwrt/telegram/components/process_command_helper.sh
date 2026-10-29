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
# Multi-argument commands (/node, /maintenance) are handled explicitly below.
# -----------------------------------------------------------------------------
CMD_DISPATCH_TABLE='
help|help_command|0
start|help_command|0
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
ctstart|ctstart_command|1
ctstop|ctstop_command|1
ctrestart|ctrestart_command|1
vmstart|vmstart_command|1
vmstop|vmstop_command|1
vmrestart|vmrestart_command|1
'

# Main Command Processor
process_command() {
    local cmd="$1"
    local chat_id="$2"
    local msg_id="$3"

    # Extract action and arguments
    local action_raw
    action_raw=$(echo "$cmd" | awk '{print $1}')
    # Strip bot username suffix if present (e.g., /status@MyBot -> /status)
    local action
    action=$(echo "$action_raw" | cut -d'@' -f1 | tr 'A-Z' 'a-z')
    local arg1
    arg1=$(echo "$cmd" | awk '{print $2}')

    # Commands that consume more than a single argument are dispatched here.
    case "$action" in
        /maintenance)
            # /maintenance [sub_cmd] [arg...]
            local full_cmd
            full_cmd=$(echo "$cmd" | cut -d' ' -f2-)
            if [ -z "$full_cmd" ]; then
                maintenance_command "$chat_id" "$msg_id"
            else
                maintenance_command "$chat_id" "$msg_id" $full_cmd
            fi
            return
            ;;

        /node)
            # /node <vm|ct> <vmid> <start|stop|restart>
            # node_command signature: (chat_id, message_id, operation, type, vmid)
            local node_type
            node_type=$(echo "$cmd" | awk '{print $2}')
            local node_vmid
            node_vmid=$(echo "$cmd" | awk '{print $3}')
            local node_op
            node_op=$(echo "$cmd" | awk '{print $4}')
            node_command "$chat_id" "$msg_id" "$node_op" "$node_type" "$node_vmid"
            return
            ;;
    esac

    # Single-argument / no-argument commands: look the handler up in the table.
    local name
    name=$(echo "$action" | cut -c2-)
    local entry
    entry=$(printf '%s\n' "$CMD_DISPATCH_TABLE" | grep "^${name}|" | head -n 1)

    if [ -n "$entry" ]; then
        local rest
        rest="${entry#*|}"
        local handler
        handler="${rest%%|*}"
        local pass_arg
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

# Action Processor for callback-based structured data (action:type:id:op)
process_action() {
    local action_data="$1"
    local chat_id="$2"
    local msg_id="$3"

    # Parse action:type:id:op
    local action_type=$(echo "$action_data" | cut -d':' -f1)
    local target_id=$(echo "$action_data" | cut -d':' -f2)
    local operation=$(echo "$action_data" | cut -d':' -f3)

    # Note: We use a specialized dispatcher for menu-driven actions to avoid complexity
    # in the main case statement, but all actions eventually resolve to commands.
    # For simplicity in this shell implementation, we map common actions to their
    # existing slash-command equivalents, but handle them via direct function calls.

    case "$action_type" in
        cmd)
            # cmd:status:0:refresh -> /status
            # cmd:list:0:refresh -> /list
            # cmd:sleep:0:execute -> /sleep
            # cmd:shutdown:0:execute -> /hostshutdown
            # cmd:reboot:0:execute -> /hostreboot
            # cmd:vm:101:start -> /vmstart 101
            # cmd:ct:100:stop -> /ctstop 100
            # cmd:maint:sys:on -> /maintenance system ON
            # ... and so on.

            local cmd_name=$(echo "$action_data" | cut -d':' -f2)
            local target=$(echo "$action_data" | cut -d':' -f3)
            local op=$(echo "$action_data" | cut -d':' -f4)

            case "$cmd_name" in
                status|list|wake|sleep|sleepforce|hostshutdown|hostshutdownforce|hostreboot|hostrebootforce|maintenance)
                    process_command "/$cmd_name" "$chat_id" "$msg_id"
                    ;;
                vm|ct)
                    # Map vm/ct target/op to specific command handlers
                    # cmd:vm:101:start -> vmstart_command 101
                    # cmd:vm:101:stop -> vmstop_command 101
                    # cmd:vm:101:restart -> vmrestart_command 101
                    local handler=""
                    if [ "$cmd_name" = "vm" ]; then
                        case "$op" in
                            start) handler="vmstart_command" ;;
                            stop) handler="vmstop_command" ;;
                            restart) handler="vmrestart_command" ;;
                        esac
                    elif [ "$cmd_name" = "ct" ]; then
                        case "$op" in
                            start) handler="ctstart_command" ;;
                            stop) handler="ctstop_command" ;;
                            restart) handler="ctrestart_command" ;;
                        esac
                    fi

                    if [ -n "$handler" ]; then
                        $handler "$chat_id" "$msg_id" "$target"
                    else
                        send_message "$chat_id" "Invalid guest operation: $op"
                    fi
                    ;;
                *)
                    send_message "$chat_id" "Unknown command: $cmd_name"
                    ;;
            esac
            ;;
        maint)
            # maint:sys:on -> /maintenance system ON
            # maint:service:101:off -> /maintenance service 101 off
            local sub_type=$(echo "$action_data" | cut -d':' -f2)
            local target=$(echo "$action_data" | cut -d':' -f3)
            local op=$(echo "$action_data" | cut -d':' -f4)

            if [ "$sub_type" = "sys" ]; then
                # maint:sys:on -> /maintenance system on
                # maint:sys:off -> /maintenance system off
                process_command "/maintenance system $op" "$chat_id" "$msg_id"
            elif [ "$sub_type" = "service" ]; then
                # maint:service:101:off -> /maintenance service 101 off
                process_command "/maintenance service $target $op" "$chat_id" "$msg_id"
            fi
            ;;
        *)
            # Fall back to sending an error message inline rather than calling send_message
            # if the function is somehow unavailable, to prevent a crash loop
            send_message "$chat_id" "Invalid action format."
            ;;
    esac
}
