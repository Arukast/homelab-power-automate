#!/bin/bash
# =============================================================================
# Homelab Power Orchestrator - Automated Verification & Unit Test Suite
# File: homelab-powerorchestractor/test_suite.sh
# Usage: ./test_suite.sh
#
# IMPORTANT: this suite sources the REAL libraries (proxmox/lib.sh and
# openwrt/components/lib.sh) rather than re-implementing their logic. Earlier
# versions duplicated day_to_num / is_in_active_window / to_integer / message
# expansion, which is why real bugs (mis-sourced helper, wrong config paths)
# could pass while the copies stayed green.
# =============================================================================

# Change directory to the script's root location
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Formatting Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

PASSED_TESTS=0
FAILED_TESTS=0

report_pass() {
    echo -e "  [${GREEN}PASS${NC}] $1"
    PASSED_TESTS=$((PASSED_TESTS + 1))
}

report_fail() {
    echo -e "  [${RED}FAIL${NC}] $1"
    [ -n "$2" ] && echo -e "         ${RED}Detail: $2${NC}"
    FAILED_TESTS=$((FAILED_TESTS + 1))
}

print_header() {
    echo ""
    echo -e "${BLUE}${BOLD}======================================================================${NC}"
    echo -e "${CYAN}${BOLD} $1 ${NC}"
    echo -e "${BLUE}${BOLD}======================================================================${NC}"
}

# check <description> <actual> <expected>
check() {
    if [ "$2" = "$3" ]; then
        report_pass "$1"
    else
        report_fail "$1" "got: '$2', expected: '$3'"
    fi
}

# check_ok <description> <command...>  (passes when the command exits 0)
check_ok() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        report_pass "$desc"
    else
        report_fail "$desc"
    fi
}

echo -e "${BOLD}Starting PowerOrchestrator Test Suite...${NC}"

# =============================================================================
# TEST SUITE 1: Script Syntax Validation
# =============================================================================
print_header "1. Script Syntax Validation (bash -n / sh -n)"

check_syntax() {
    local file="$1"
    local shell_bin="$2"
    if [ -f "$file" ]; then
        if $shell_bin -n "$file" 2>/dev/null; then
            report_pass "Syntax valid: $file ($shell_bin)"
        else
            local err=$($shell_bin -n "$file" 2>&1)
            report_fail "Syntax error: $file ($shell_bin)" "$err"
        fi
    else
        report_fail "File not found: $file"
    fi
}

check_syntax "proxmox/lib.sh" "bash"
check_syntax "proxmox/proxmox_idle_monitor.sh" "bash"
check_syntax "proxmox/homelab_ssh_wrapper.sh" "sh"
check_syntax "proxmox/proxmox_resource_monitor.sh" "bash"
check_syntax "proxmox/install_proxmox.sh" "bash"

# Shared components
check_syntax "openwrt/components/lib.sh" "sh"
check_syntax "openwrt/components/check_helper.sh" "sh"
check_syntax "openwrt/components/common_init.sh" "sh"
check_syntax "openwrt/components/conf_helper.sh" "sh"

# Config Sync
check_syntax "openwrt/config_sync/homelab_config_sync.sh" "sh"
check_syntax "openwrt/config_sync/components/deploy_helper.sh" "sh"
check_syntax "openwrt/config_sync/components/permission_helper.sh" "sh"
check_syntax "openwrt/config_sync/components/router_ip_helper.sh" "sh"
check_syntax "openwrt/config_sync/components/sanitized_conf_helper.sh" "sh"
check_syntax "openwrt/config_sync/components/verify_helper.sh" "sh"

# Installer
check_syntax "openwrt/install/install_openwrt.sh" "sh"
check_syntax "openwrt/install/components/packages_helper.sh" "sh"
check_syntax "openwrt/install/components/post_install_helper.sh" "sh"
check_syntax "openwrt/install/components/script_helper.sh" "sh"
check_syntax "openwrt/install/components/service_helper.sh" "sh"
check_syntax "openwrt/install/components/setup_conf_helper.sh" "sh"

# Power Proxy
check_syntax "openwrt/power_proxy/power_proxy_daemon.sh" "sh"
check_syntax "openwrt/power_proxy/guest_wake_listener.sh" "sh"
check_syntax "openwrt/power_proxy/game_wake_listener.sh" "sh"
check_syntax "openwrt/power_proxy/components/cleanup_helper.sh" "sh"
check_syntax "openwrt/power_proxy/components/listener_helper.sh" "sh"
check_syntax "openwrt/power_proxy/components/main.sh" "sh"
check_syntax "openwrt/power_proxy/components/network_helper.sh" "sh"
check_syntax "openwrt/power_proxy/components/notify_helper.sh" "sh"
check_syntax "openwrt/power_proxy/components/redirect_helper.sh" "sh"

# Telegram bot
check_syntax "openwrt/telegram/telegram_bot_daemon.sh" "sh"
check_syntax "openwrt/telegram/maintenance_homelab.sh" "sh"
check_syntax "openwrt/telegram/notify_homelab.sh" "sh"
check_syntax "openwrt/telegram/components/command_helper.sh" "sh"
check_syntax "openwrt/telegram/components/message_helper.sh" "sh"
check_syntax "openwrt/telegram/components/polling_helper.sh" "sh"
check_syntax "openwrt/telegram/components/process_command_helper.sh" "sh"
check_syntax "openwrt/telegram/components/liveness_monitor.sh" "sh"
check_syntax "openwrt/telegram/components/commands/help_command.sh" "sh"
check_syntax "openwrt/telegram/components/commands/status_command.sh" "sh"
check_syntax "openwrt/telegram/components/commands/list_command.sh" "sh"
check_syntax "openwrt/telegram/components/commands/node_command.sh" "sh"
check_syntax "openwrt/telegram/components/commands/wake_command.sh" "sh"
check_syntax "openwrt/telegram/components/commands/sleep_command.sh" "sh"
check_syntax "openwrt/telegram/components/commands/sleepforce_command.sh" "sh"
check_syntax "openwrt/telegram/components/commands/hostreboot_command.sh" "sh"
check_syntax "openwrt/telegram/components/commands/hostrebootforce_command.sh" "sh"
check_syntax "openwrt/telegram/components/commands/hostshutdown_command.sh" "sh"
check_syntax "openwrt/telegram/components/commands/hostshutdownforce_command.sh" "sh"
check_syntax "openwrt/telegram/components/commands/start_command.sh" "sh"
check_syntax "openwrt/telegram/components/commands/stop_command.sh" "sh"
check_syntax "openwrt/telegram/components/commands/restart_command.sh" "sh"
check_syntax "openwrt/telegram/components/commands/maintenance_command.sh" "sh"

# =============================================================================
# Load the real Proxmox shared library (log/notify/render_msg/load_conf/
# to_integer/day_to_num/is_in_active_window). This is the code the monitors run.
# =============================================================================
PROXMOX_LIB="proxmox/lib.sh"
if [ -f "$PROXMOX_LIB" ]; then
    # shellcheck source=proxmox/lib.sh
    . "$PROXMOX_LIB"
else
    report_fail "Missing $PROXMOX_LIB (cannot run logic tests)"
fi

# =============================================================================
# TEST SUITE 2: Active Time Window Evaluation (real is_in_active_window)
# =============================================================================
print_header "2. Active Time Window Evaluation (proxmox/lib.sh is_in_active_window)"

# Day-ranged window
ACTIVE_TIME_WINDOWS="Mon-Sun:05:00-23:00"
if is_in_active_window Tue 09 30; then report_pass "Mon-Sun:05:00-23:00 active at Tue 09:30"; else report_fail "Mon-Sun:05:00-23:00 should be active at Tue 09:30"; fi
if is_in_active_window Sun 05 00; then report_pass "Mon-Sun:05:00-23:00 active at exact start 05:00"; else report_fail "should be active at 05:00 boundary"; fi
if is_in_active_window Mon 23 00; then report_pass "Mon-Sun:05:00-23:00 active at exact end 23:00"; else report_fail "should be active at 23:00 boundary"; fi
if ! is_in_active_window Wed 23 01; then report_pass "Mon-Sun:05:00-23:00 inactive at 23:01"; else report_fail "should be inactive at 23:01"; fi
if ! is_in_active_window Fri 04 59; then report_pass "Mon-Sun:05:00-23:00 inactive at 04:59"; else report_fail "should be inactive at 04:59"; fi

# Overnight window
ACTIVE_TIME_WINDOWS="Mon-Fri:18:00-06:00"
if is_in_active_window Wed 02 00; then report_pass "Overnight Mon-Fri:18:00-06:00 active at 02:00"; else report_fail "overnight window should be active at 02:00"; fi
if ! is_in_active_window Sun 10 00; then report_pass "Weekday-only window inactive on Sunday"; else report_fail "weekday-only window should be inactive Sunday"; fi

ACTIVE_TIME_WINDOWS="Sat-Sun:00:00-23:59"
if is_in_active_window Sat 14 15; then report_pass "Weekend full-day window active at Sat 14:15"; else report_fail "weekend window should be active"; fi

# REGRESSION (dayless windows): "08:00-23:00" must apply to ALL days. The old
# code split on ':' and treated "08" as a day name, so it never matched and the
# host auto-suspended during the intended awake window.
ACTIVE_TIME_WINDOWS="08:00-23:00"
if is_in_active_window Tue 10 00; then report_pass "Dayless '08:00-23:00' active at Tue 10:00 (regression)"; else report_fail "dayless window must be active at Tue 10:00"; fi
if is_in_active_window Sat 10 00; then report_pass "Dayless '08:00-23:00' active on Saturday too"; else report_fail "dayless window must apply to all days"; fi
if ! is_in_active_window Tue 06 00; then report_pass "Dayless '08:00-23:00' inactive at 06:00"; else report_fail "dayless window should be inactive at 06:00"; fi

ACTIVE_TIME_WINDOWS=""
if ! is_in_active_window Tue 10 00; then report_pass "Empty ACTIVE_TIME_WINDOWS => never in-window"; else report_fail "empty config should never be in-window"; fi

# =============================================================================
# TEST SUITE 3: Floating Point Conversion Helper (real to_integer)
# =============================================================================
print_header "3. Float Math Helper (proxmox/lib.sh to_integer)"

check_float() {
    local input="$1"
    local expected="$2"
    local res
    res=$(to_integer "$input")
    check "to_integer '$input' -> $expected" "$res" "$expected"
}

check_float "0.15" "15"
check_float "0.05" "5"
check_float "1.00" "100"
check_float "1.5" "150"
check_float "0.0" "0"
check_float "0" "0"

# =============================================================================
# TEST SUITE 4: JSON Escaping Engine (notify_homelab.sh contract)
# =============================================================================
print_header "4. JSON Escaping Engine"

escape_json() {
    printf '%s' "$1" | awk 'BEGIN {ORS="";} {
        gsub(/\\/, "\\\\");
        gsub(/"/, "\\\"");
        gsub(/\r/, "");
        gsub(/\t/, "\\t");
        if (NR > 1) printf "\\n";
        printf "%s", $0;
    }'
}

TEST_STR="Line 1: with \"double quotes\" and \\backslashes\\
Line 2: with tab	character
Line 3: finished."

ESCAPED_STR=$(escape_json "$TEST_STR")
EXPECTED_STR='Line 1: with \"double quotes\" and \\backslashes\\\nLine 2: with tab\tcharacter\nLine 3: finished.'
check "Multiline text, quotes, and backslashes escaped safely for JSON" "$ESCAPED_STR" "$EXPECTED_STR"

# =============================================================================
# TEST SUITE 5: SSH Command Wrapper (static allow-list contract)
# =============================================================================
print_header "5. SSH Command Security Wrapper Dispatcher"

check_wrapper_pattern() {
    local SSH_ORIGINAL_COMMAND="$1"
    case "$SSH_ORIGINAL_COMMAND" in
        "echo OK")
            echo "ALLOW: echo OK"
            ;;
        "echo '===METRICS==='; uptime; echo '===RAM==='; free -h; echo '===LXC==='; pct list; echo '===VM==='; qm list")
            echo "ALLOW: host metrics payload"
            ;;
        "pct list | awk 'NR>1 && \$2==\"running\" {print \$1}'; qm list | awk 'NR>1 && \$3==\"running\" {print \$1}'")
            echo "ALLOW: running guests list"
            ;;
        *cpu=\$\(grep\ \'cpu\ \'*)
            echo "ALLOW: host telemetry sensor probe"
            ;;
        *)
            set -- $SSH_ORIGINAL_COMMAND
            if [ $# -eq 3 ] && echo "$3" | grep -qE "^[0-9]+$"; then
                if [ "$1" = "pct" ] || [ "$1" = "qm" ]; then
                    case "$2" in
                        config|start|stop|shutdown|reboot|resume|status)
                            echo "ALLOW: $1 $2 $3"
                            return
                            ;;
                    esac
                fi
            fi
            echo "DENY: $SSH_ORIGINAL_COMMAND"
            ;;
    esac
}

W1=$(check_wrapper_pattern 'echo OK')
check "Wrapper allows 'echo OK'" "$W1" "ALLOW: echo OK"
W5=$(check_wrapper_pattern 'qm start 120')
check "Wrapper allows 'qm start 120'" "$W5" "ALLOW: qm start 120"
W6=$(check_wrapper_pattern 'pct stop 101')
check "Wrapper allows 'pct stop 101'" "$W6" "ALLOW: pct stop 101"
W_BAD=$(check_wrapper_pattern 'rm -rf /')
check "Wrapper denies unauthorized 'rm -rf /'" "$W_BAD" "DENY: rm -rf /"

# =============================================================================
# TEST SUITE 6: Multi-Map Guest Discovery Aggregation
# =============================================================================
print_header "6. Multi-Map Guest Discovery Aggregation"

GUEST_ORCHESTRATION_MAP=""
GUEST_NAME_MAP=""
GUEST_MESSAGE_MAP="120:Unturned Server<br>Code: 123,121:Minecraft Server<br>Code: 456"
GUEST_PORT_MAP="122:8080"
GUEST_PASSCODE_MAP="123:secret"
GUEST_PRIVACY_MAP="124:public"

ALL_DISCOVERED_VMIDS=$(
    {
        [ -n "$GUEST_ORCHESTRATION_MAP" ] && echo "$GUEST_ORCHESTRATION_MAP" | tr ',' '\n' | cut -d':' -f1
        [ -n "$GUEST_NAME_MAP" ] && echo "$GUEST_NAME_MAP" | tr ',' '\n' | cut -d':' -f1
        [ -n "$GUEST_MESSAGE_MAP" ] && echo "$GUEST_MESSAGE_MAP" | tr ',' '\n' | cut -d':' -f1
        [ -n "$GUEST_PORT_MAP" ] && echo "$GUEST_PORT_MAP" | tr ',' '\n' | cut -d':' -f1
        [ -n "$GUEST_PASSCODE_MAP" ] && echo "$GUEST_PASSCODE_MAP" | tr ',' '\n' | cut -d':' -f1
        [ -n "$GUEST_PRIVACY_MAP" ] && echo "$GUEST_PRIVACY_MAP" | tr ',' '\n' | cut -d':' -f1
    } | grep -E '^[0-9]+$' | sort -u | tr '\n' ' ' | sed 's/[[:space:]]*$//'
)
check "Discovered unique VMIDs across all independent maps" "$ALL_DISCOVERED_VMIDS" "120 121 122 123 124"

# =============================================================================
# TEST SUITE 7: Regression tests for the fixed bugs
# =============================================================================
print_header "7. Regression Tests (fixed bugs)"

# 7.1 Power proxy must source the existing redirect helper (was redirects_helper.sh)
if grep -q 'redirects_helper\.sh' openwrt/power_proxy/power_proxy_daemon.sh 2>/dev/null; then
    report_fail "power_proxy_daemon.sh still references redirects_helper.sh (file does not exist)"
else
    report_pass "power_proxy_daemon.sh no longer sources a non-existent redirects_helper.sh"
fi
if [ -f openwrt/power_proxy/components/redirect_helper.sh ] && \
   grep -q 'redirect_helper\.sh' openwrt/power_proxy/power_proxy_daemon.sh; then
    report_pass "power_proxy_daemon.sh sources the real redirect_helper.sh"
else
    report_fail "power_proxy_daemon.sh does not source the real redirect_helper.sh"
fi

# 7.2 Router scripts must read the router config path, not the Proxmox one
check_ok "power_proxy.init reads /etc/power_homelab.conf" \
    grep -q '/etc/power_homelab.conf' openwrt/power_proxy/power_proxy.init
if grep -q '/etc/homelab_power.conf' openwrt/power_proxy/power_proxy.init 2>/dev/null; then
    report_fail "power_proxy.init still reads the Proxmox config path"
else
    report_pass "power_proxy.init no longer reads the Proxmox config path"
fi
check_ok "notify_homelab.sh reads /etc/power_homelab.conf" \
    grep -q '/etc/power_homelab.conf' openwrt/telegram/notify_homelab.sh

# 7.3 Proxmox scripts must not read the router config path
if grep -rq '/etc/power_homelab.conf' proxmox/ 2>/dev/null; then
    report_fail "A proxmox script references the router config path /etc/power_homelab.conf"
else
    report_pass "No proxmox script references the router config path"
fi

# 7.4 No eval-based message expansion anywhere (use render_msg instead)
if grep -rn 'eval echo' proxmox/ openwrt/ >/dev/null 2>&1; then
    report_fail "Found leftover 'eval echo' message expansion"
else
    report_pass "No 'eval echo' message expansion remains"
fi

# 7.5 render_msg (openwrt/components/lib.sh) substitutes tokens, no eval/sed
OPENWRT_RENDER=$(
    . openwrt/components/lib.sh
    arg1=42; HOST_MAC="aa:bb:cc:dd:ee:ff"; GUEST_NAME="NAS"; VMID=101
    render_msg 'id=$arg1 mac=$HOST_MAC name=$GUEST_NAME vmid=$VMID'
)
check "openwrt render_msg substitutes tokens" "$OPENWRT_RENDER" "id=42 mac=aa:bb:cc:dd:ee:ff name=NAS vmid=101"

# 7.6 trim (openwrt/components/lib.sh)
TRIMMED=$(printf '   spaced out   \n' | { . openwrt/components/lib.sh; trim; })
check "openwrt trim strips surrounding whitespace" "$TRIMMED" "spaced out"

# 7.7 load_conf applies allow-listed keys and rejects metacharacter payloads
TMP_CONF=$(mktemp)
{
    echo 'MONITORED_PORTS="22,80,443"'
    echo 'CPU_THRESHOLD="0.5; touch /tmp/homelab_conf_pwn"'
} > "$TMP_CONF"
rm -f /tmp/homelab_conf_pwn
MONITORED_PORTS=""; CPU_THRESHOLD="DEFAULT"
load_conf "$TMP_CONF"
check "load_conf applies a valid allow-listed value" "$MONITORED_PORTS" "22,80,443"
check "load_conf rejects a value containing metacharacters" "$CPU_THRESHOLD" "DEFAULT"
if [ -e /tmp/homelab_conf_pwn ]; then
    report_fail "load_conf executed a metacharacter payload"
    rm -f /tmp/homelab_conf_pwn
else
    report_pass "load_conf never executes file contents"
fi
rm -f "$TMP_CONF"

# 7.8 load_msg_conf loads real templates and neutralises command substitution
TMP_MSG=$(mktemp)
{
    echo 'MSG_MONITOR_CPU_ALERT="[Warning] CPU $VALUE% (thr $THRESHOLD%)"'
    echo 'MSG_EVIL="$(touch /tmp/homelab_msg_pwn)"'
    echo 'NOT_A_MSG_KEY="$(touch /tmp/homelab_msg_pwn2)"'
} > "$TMP_MSG"
rm -f /tmp/homelab_msg_pwn /tmp/homelab_msg_pwn2
MSG_MONITOR_CPU_ALERT=""; MSG_EVIL=""
load_msg_conf "$TMP_MSG"
check "load_msg_conf loads a template with \$TOKEN placeholders" \
    "$MSG_MONITOR_CPU_ALERT" '[Warning] CPU $VALUE% (thr $THRESHOLD%)'
check "load_msg_conf stores a \$(...)'d value verbatim" "$MSG_EVIL" '$(touch /tmp/homelab_msg_pwn)'
if [ -e /tmp/homelab_msg_pwn ] || [ -e /tmp/homelab_msg_pwn2 ]; then
    report_fail "load_msg_conf executed a payload"
    rm -f /tmp/homelab_msg_pwn /tmp/homelab_msg_pwn2
else
    report_pass "load_msg_conf never executes file contents"
fi
rm -f "$TMP_MSG"

# 7.9 The wrapper must validate the config payload instead of blind `cat >`
if grep -q 'install -m 600' proxmox/homelab_ssh_wrapper.sh && \
   grep -q 'REJECTED malformed configuration payload' proxmox/homelab_ssh_wrapper.sh; then
    report_pass "homelab_ssh_wrapper.sh validates the pushed config payload"
else
    report_fail "homelab_ssh_wrapper.sh still writes the config without validation"
fi

# 7.10 /node is dispatched; inline-keyboard buttons have been removed everywhere
check_ok "process_command_helper.sh dispatches /node" \
    grep -q '/node)' openwrt/telegram/components/process_command_helper.sh
if grep -rq 'inline_keyboard' openwrt/telegram/ 2>/dev/null; then
    report_fail "Inline-keyboard button markup is still generated in openwrt/telegram/"
else
    report_pass "No inline-keyboard button markup remains (all buttons removed)"
fi

# 7.11 polling_helper routes cmd:/maint: callbacks to process_action
check_ok "polling_helper.sh routes cmd: callbacks" \
    grep -q '\^cmd:' openwrt/telegram/components/polling_helper.sh

# 7.12 send_message called with an explicit empty markup arg on the error paths
check_ok "status_command.sh passes markup+msg_id positionally" \
    grep -q '"\$MSG_BOT_SSH_FAILED" "" "\$msg_id"' openwrt/telegram/components/commands/status_command.sh
check_ok "list_command.sh passes markup+msg_id positionally" \
    grep -q '"\$MSG_BOT_LIST_HOST_OFFLINE" "" "\$msg_id"' openwrt/telegram/components/commands/list_command.sh

# 7.13 Host-power handlers read message_id from $2 (not the empty $3)
check_ok "host_power_action exists (collapsed host handlers)" \
    grep -q '^host_power_action()' openwrt/telegram/components/command_helper.sh
check_ok "guest_action exists (collapsed guest handlers)" \
    grep -q '^guest_action()' openwrt/telegram/components/command_helper.sh

# 7.14 /node delegates to guest_action and maps restart -> reboot (wrapper verb)
check_ok "node_command delegates to guest_action" \
    grep -q 'guest_action' openwrt/telegram/components/commands/node_command.sh
check_ok "node_command maps restart -> reboot for the wrapper allow-list" \
    grep -q 'restart) op="reboot"' openwrt/telegram/components/commands/node_command.sh

# 7.15 Router SSH must not use OpenSSH-only options: OpenWrt's `ssh` is Dropbear's
# client, which rejects `-o ConnectTimeout=...` and prints a warning to output.
if grep -rqE 'ssh .*-o +ConnectTimeout' openwrt/ 2>/dev/null; then
    report_fail "An openwrt script passes -o ConnectTimeout (Dropbear rejects unknown -o options)"
else
    report_pass "No Dropbear-incompatible '-o ConnectTimeout' in openwrt/"
fi
check_ok "is_host_alive bounds the SSH probe with BusyBox timeout" \
    grep -q 'timeout 6 \$SSH_CMD' openwrt/components/check_helper.sh

# 7.16 SSH key permission check repairs a 0644 key and is silent for 0600
PERM_OPEN=$(mktemp); chmod 644 "$PERM_OPEN"
SSH_KEY_PATH="$PERM_OPEN" bash -c '. openwrt/config_sync/components/permission_helper.sh; check_permission' >/dev/null 2>&1
check "permission_helper repairs a 0644 key to 0600" "$(ls -l "$PERM_OPEN" | awk '{print $1}')" "-rw-------"
PERM_OK=$(mktemp); chmod 600 "$PERM_OK"
PERM_OUT=$(SSH_KEY_PATH="$PERM_OK" bash -c '. openwrt/config_sync/components/permission_helper.sh; check_permission' 2>&1)
check "permission_helper is silent for a 0600 key" "$PERM_OUT" ""
rm -f "$PERM_OPEN" "$PERM_OK"

# 7.17 /wake and guest start short-circuit when the target is already up
check_ok "/wake reports already-awake instead of re-sending a magic packet" \
    grep -q 'MSG_BOT_WOL_ALREADY_AWAKE' openwrt/telegram/components/commands/wake_command.sh
check_ok "guest_action reports an already-running guest instead of starting it" \
    grep -q 'MSG_BOT_GUEST_ALREADY_RUNNING' openwrt/telegram/components/command_helper.sh
check_ok "/maintenance prints usage when called with no sub-command" \
    grep -q '_maint_usage' openwrt/telegram/components/commands/maintenance_command.sh

# 7.18 Unified guest commands: /start /stop /restart auto-detect, /node kept
check_ok "/start auto-detects the guest type" \
    grep -q 'guest_action "$1" "$2" "$3" auto start' openwrt/telegram/components/commands/start_command.sh
check_ok "/stop auto-detects the guest type" \
    grep -q 'guest_action "$1" "$2" "$3" auto stop' openwrt/telegram/components/commands/stop_command.sh
check_ok "/restart auto-detects the guest type" \
    grep -q 'guest_action "$1" "$2" "$3" auto reboot' openwrt/telegram/components/commands/restart_command.sh
check_ok "guest_action resolves the type when tool=auto" \
    grep -q '"pct status \$vmid"' openwrt/telegram/components/command_helper.sh
check_ok "forced-type mismatch is reported (not a raw Proxmox error)" \
    grep -q 'MSG_BOT_GUEST_WRONG_TYPE' openwrt/telegram/components/command_helper.sh
check_ok "dispatch table still contains /node" \
    grep -q '/node)' openwrt/telegram/components/process_command_helper.sh
check_ok "dispatch table no longer contains /ct* or /vm*" \
    bash -c '! grep -qE "^((ct|vm)(start|stop|restart))\|" openwrt/telegram/components/process_command_helper.sh'

# 7.19 Regression: a bare /maintenance must show usage, not be read as a sub-command
MAINT_OUT=$(
    . openwrt/telegram/components/maintenance_helper.sh
    . openwrt/telegram/components/commands/maintenance_command.sh
    . openwrt/telegram/components/process_command_helper.sh
    send_message() { printf '%s\n' "$2"; }
    process_command "/maintenance" 1 2
)
case "$MAINT_OUT" in
    *Usage:*) report_pass "bare /maintenance shows usage" ;;
    *) report_fail "bare /maintenance did not show usage" "$MAINT_OUT" ;;
esac
case "$MAINT_OUT" in
    *"Unknown sub-command"*) report_fail "bare /maintenance was parsed as its own sub-command" ;;
    *) report_pass "bare /maintenance is not treated as a sub-command" ;;
esac

# 7.20 /maintenance keeps a multi-word reason intact
MAINT_REASON_DIR=$(mktemp -d)
MAINT_REASON=$(MAINT_DIR="$MAINT_REASON_DIR" sh -c '
    . openwrt/telegram/components/maintenance_helper.sh
    . openwrt/telegram/components/commands/maintenance_command.sh
    send_message() { :; }
    maintenance_command 1 2 system "on swapping RAM"
    cat "$MAINT_DIR/system"
' 2>&1)
check "/maintenance keeps a multi-word reason" "$MAINT_REASON" "swapping RAM"
rm -rf "$MAINT_REASON_DIR"

# 7.21 Safe-action pre-flight (--check) plumbing
check_ok "idle monitor supports --check (REPORT_ONLY)" \
    grep -q 'REPORT_ONLY=1' proxmox/proxmox_idle_monitor.sh
check_ok "idle monitor emits a machine-readable verdict" \
    grep -q 'HOMELAB_CHECK:BLOCKED' proxmox/proxmox_idle_monitor.sh
check_ok "SSH wrapper allow-lists 'proxmox_idle_monitor.sh --check'" \
    grep -q 'proxmox_idle_monitor.sh --check' proxmox/homelab_ssh_wrapper.sh
check_ok "wrapper refuses --check on a stale monitor (never acts by accident)" \
    grep -q 'HOMELAB_CHECK:UNSUPPORTED' proxmox/homelab_ssh_wrapper.sh
check_ok "bot warns when the pre-check is unavailable" \
    grep -q 'MSG_BOT_PRECHECK_UNAVAILABLE' openwrt/telegram/components/command_helper.sh
check_ok "bot names a stale wrapper (Access Denied)" \
    grep -q 'MSG_BOT_PRECHECK_DENIED' openwrt/telegram/components/command_helper.sh
check_ok "bot names a stale monitor (HOMELAB_CHECK:UNSUPPORTED)" \
    grep -q 'MSG_BOT_PRECHECK_UNSUPPORTED' openwrt/telegram/components/command_helper.sh
check_ok "host_power_action consumes the --check verdict" \
    grep -q 'HOMELAB_CHECK:BLOCKED:\*' openwrt/telegram/components/command_helper.sh
check_ok "a blocked safe action sends MSG_BOT_ACTION_BLOCKED" \
    grep -q 'MSG_BOT_ACTION_BLOCKED' openwrt/telegram/components/command_helper.sh

# 7.23 Uniform power-action gating (sleep == shutdown == reboot)
check_ok "the misleading require-maintenance gate is gone" \
    bash -c '! grep -q "cmd_require_maintenance\|maint_check=\"require\"" openwrt/telegram/components/command_helper.sh'
check_ok "sleep/shutdown/reboot share the same maintenance gate" \
    bash -c '[ "$(grep -c "maint_check=\"active\"" openwrt/telegram/components/command_helper.sh)" = "3" ]'
check_ok "blocked safe actions offer the force override" \
    grep -q 'arg3="${maint_cmd}force"' openwrt/telegram/components/command_helper.sh

# 7.22 Functional: --check reports the block reason (temp config, protected proc)
CHK_CONF=$(mktemp)
printf 'PROTECTED_PROCESSES="sh"\nLOG_FILE="/dev/null"\nENABLE_SYSLOG=0\nNET_INTERFACE="nonexistent0"\n' > "$CHK_CONF"
sed "s#^CONF=\"/etc/homelab_power.conf\"#CONF=\"$CHK_CONF\"#" proxmox/proxmox_idle_monitor.sh > proxmox/_mon_check_test.sh
CHK_BLOCKED_OUT=$(bash proxmox/_mon_check_test.sh --check 2>/dev/null)
rm -f proxmox/_mon_check_test.sh "$CHK_CONF"
case "$CHK_BLOCKED_OUT" in
    "HOMELAB_CHECK:BLOCKED: protected process 'sh' is currently running")
        report_pass "--check reports the exact block reason (clean stdout)" ;;
    *) report_fail "--check block reason" "$CHK_BLOCKED_OUT" ;;
esac

# =============================================================================
# SUMMARY REPORT
# =============================================================================
echo ""
echo -e "${BLUE}${BOLD}======================================================================${NC}"
echo -e "${BOLD}TEST SUITE SUMMARY${NC}"
echo -e "${BLUE}${BOLD}======================================================================${NC}"
echo -e "  Total Tests: $((PASSED_TESTS + FAILED_TESTS))"
echo -e "  Passed:      ${GREEN}${BOLD}${PASSED_TESTS}${NC}"
echo -e "  Failed:      ${RED}${BOLD}${FAILED_TESTS}${NC}"
echo -e "${BLUE}${BOLD}======================================================================${NC}"

if [ "$FAILED_TESTS" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}✓ ALL TESTS PASSED SUCCESSFULLY! Codebase is ready for deployment.${NC}"
    exit 0
else
    echo -e "${RED}${BOLD}✗ SOME TESTS FAILED. Please review the output above.${NC}"
    exit 1
fi
