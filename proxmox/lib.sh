#!/bin/bash
# =============================================================================
# Proxmox VE Homelab Power Suite - Shared Library
# File: /usr/local/lib/homelab/lib.sh
#
# Sourced by proxmox_idle_monitor.sh and proxmox_resource_monitor.sh (via
# /usr/local/lib/homelab/lib.sh, with a fallback to the caller's own directory
# so the monitors can also be exercised straight from the repository).
#
# SECURITY: The configuration files handled here are written by the OpenWrt
# router over SSH (through homelab_ssh_wrapper.sh). They must NEVER be
# `source`d/eval'd blindly: doing so as root turns a compromised router into a
# root RCE. load_conf()/load_msg_conf() only apply allowlisted KEY= lines and
# only after strict character validation.
# =============================================================================

# Keys permitted in /etc/homelab_power.conf (order-independent allowlist).
HOMELAB_CONF_KEYS="CPU_THRESHOLD SCALE_CPU_THRESHOLD_BY_CORES NET_INTERFACE NET_THRESHOLD_KBPS MONITORED_PORTS HOST_SSH_PORT LXC_SUSPEND_METHOD VM_SUSPEND_METHOD PROTECTED_PROCESSES GUEST_ORCHESTRATION_MAP EXEMPT_SHUTDOWN_GUESTS ACTIVE_TIME_WINDOWS GUEST_NAME_MAP GUEST_PORT_MAP LOG_FILE ENABLE_SYSLOG MONITOR_CPU_THRESHOLD_PCT MONITOR_RAM_THRESHOLD_PCT MONITOR_DISK_THRESHOLD_PCT MONITOR_DISK_PATHS MONITOR_SERVICES MONITOR_ZFS_POOLS MONITOR_CRITICAL_GUESTS MONITOR_COOLDOWN_SEC NOTIFICATION_URL"

# A whole config line is only accepted when key and (optionally quoted) value
# are built exclusively from this safe character set. No metacharacters.
HOMELAB_CONF_LINE_RE='^[A-Z_][A-Z0-9_]*="?[A-Za-z0-9 ,._/:+=-]*"?$'

# --- Logging ----------------------------------------------------------------
# Timestamped append to $LOG_FILE plus an optional syslog mirror. The logger
# tag is taken from $LOG_TAG so each monitor keeps its historical identity.
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" >> "$LOG_FILE"
    if [ "${ENABLE_SYSLOG:-0}" -eq 1 ]; then
        logger -t "${LOG_TAG:-proxmox-power}" "$1"
    fi
    echo "$msg"
}

# --- Notification -----------------------------------------------------------
# Log the message and (if configured) POST it to $NOTIFICATION_URL.
notify() {
    local msg="$1"
    log "NOTIFICATION: $msg"
    if [ -n "${NOTIFICATION_URL:-}" ]; then
        curl -s --connect-timeout 2 --max-time 5 -X POST \
            --data-urlencode "msg=$msg" \
            "$NOTIFICATION_URL" >/dev/null &
    fi
}

# --- Message rendering ------------------------------------------------------
# Replace the literal $TOKEN placeholders with the CURRENT values of the
# corresponding shell variables. Pure parameter expansion only - no eval, no
# sed, no code execution. $TOKEN ids never overlap, so order is irrelevant.
render_msg() {
    local tpl="$1"

    # patsub_replacement (bash >= 5.2) makes '&' in a replacement expand to the
    # matched text. Turn it off for the duration so values are inserted
    # verbatim, then restore the previous setting.
    local patsub_was_on=1
    shopt -q patsub_replacement 2>/dev/null && patsub_was_on=0
    shopt -u patsub_replacement 2>/dev/null

    tpl="${tpl//'$GUEST_NAME'/${GUEST_NAME:-}}"
    tpl="${tpl//'$VMID'/${VMID:-}}"
    tpl="${tpl//'$TIMEOUT_MIN'/${TIMEOUT_MIN:-}}"
    tpl="${tpl//'$VALUE'/${VALUE:-}}"
    tpl="${tpl//'$THRESHOLD'/${THRESHOLD:-}}"
    # The disk path is carried in HL_PATH, never PATH: a variable literally named
    # PATH would shadow the command search path for the calling function body.
    tpl="${tpl//'$PATH'/${HL_PATH:-}}"
    tpl="${tpl//'$SERVICE'/${SERVICE:-}}"
    tpl="${tpl//'$POOL'/${POOL:-}}"

    [ "$patsub_was_on" -eq 0 ] && shopt -s patsub_replacement 2>/dev/null
    printf '%s' "$tpl"
}

# --- Hardened config loader -------------------------------------------------
# Apply only allowlisted `KEY=` assignments from <file>, and only when the whole
# line consists purely of safe characters. Nothing is `source`d. Anything that
# does not validate is ignored. Returns 0 even for a missing file.
load_conf() {
    local file="$1"
    [ -f "$file" ] || return 0

    local key line
    for key in $HOMELAB_CONF_KEYS; do
        line=$(grep -E "^${key}=" "$file" 2>/dev/null | head -n 1)
        [ -z "$line" ] && continue
        if printf '%s\n' "$line" | grep -qE "$HOMELAB_CONF_LINE_RE"; then
            eval "$line"
        fi
    done
    return 0
}

# --- Hardened messages loader ----------------------------------------------
# Message templates legitimately contain characters the strict config charset
# forbids ($TOKEN placeholders, '*', '[', '%', emoji), so the regex gate used by
# load_conf() cannot be reused here. Safety instead comes from NEVER re-parsing
# the value as code: the line is split into KEY/VALUE, the KEY is required to be
# a plain MSG_* name, and the value is applied through a single indirection
# (`eval "$key=\$val"`) in which $val is expanded as DATA only. A ';', '$(...)'
# or backtick inside a template is therefore stored verbatim and never executed.
# (Multi-line templates are not supported; PVE only consumes the single-line
# MSG_PROXMOX_*/MSG_MONITOR_* values.)
load_msg_conf() {
    local file="$1"
    [ -f "$file" ] || return 0

    local line key val
    while IFS= read -r line; do
        case "$line" in
            ''|\#*) continue ;;
            MSG_*=*) ;;
            *) continue ;;
        esac
        key="${line%%=*}"
        val="${line#*=}"
        case "$key" in
            MSG_[A-Z0-9_]*) ;;
            *) continue ;;
        esac
        # Strip one layer of surrounding double quotes, if present.
        case "$val" in
            \"*\") val="${val#\"}"; val="${val%\"}" ;;
        esac
        # Safe indirect assignment: $val is expanded as data, never re-parsed.
        eval "$key=\$val"
    done < "$file"
    return 0
}

# --- POSIX Float Math Helpers (Avoids bc dependency) ---
to_integer() {
    local val="$1"
    local int="${val%.*}"
    local dec=""
    if [ "$int" != "$val" ]; then
        dec="${val#*.}"
    fi
    [ -z "$int" ] && int=0
    [ -z "$dec" ] && dec=0

    dec="${dec}00"
    dec="${dec:0:2}"

    local res="${int}${dec}"
    while [[ $res == 0* && ${#res} -gt 1 ]]; do
        res="${res#0}"
    done
    echo "$res"
}

# --- Smart Wake Scheduling Helpers ---
day_to_num() {
    case "$1" in
        Mon) echo 1 ;;
        Tue) echo 2 ;;
        Wed) echo 3 ;;
        Thu) echo 4 ;;
        Fri) echo 5 ;;
        Sat) echo 6 ;;
        Sun) echo 7 ;;
        *) echo 0 ;;
    esac
}

is_in_active_window() {
    [ -z "$ACTIVE_TIME_WINDOWS" ] && return 1

    # Optional day/hour/minute arguments make the function deterministic under
    # test; the running monitors call it with no arguments and use the clock.
    local curr_day curr_hour curr_min
    if [ $# -ge 3 ]; then
        curr_day="$1"; curr_hour="$2"; curr_min="$3"
    else
        curr_day=$(LC_ALL=C date +%a)
        curr_hour=$(date +%H)
        curr_min=$(date +%M)
    fi
    local curr_day_num=$(day_to_num "$curr_day")

    # Safely convert to integer minutes of day using base-10
    local ch=$((10#$curr_hour))
    local cm=$((10#$curr_min))
    local curr_time_m=$(( ch * 60 + cm ))

    for window in $(echo "$ACTIVE_TIME_WINDOWS" | tr ',' ' '); do
        local days=""
        local times=""
        # The pre-colon token is only a day spec when it actually looks like one
        # (e.g. "Mon-Sun", "All", "Sat"). A bare time window such as
        # "08:00-23:00" has "08" before the first colon, which is NOT a day, so
        # treat the whole token as the time range and apply it to every day.
        local pre_days="${window%%:*}"
        if [ "$pre_days" != "$window" ] && echo "$pre_days" | grep -qE '^(All|Mon|Tue|Wed|Thu|Fri|Sat|Sun)(-(All|Mon|Tue|Wed|Thu|Fri|Sat|Sun))?$'; then
            days="$pre_days"
            times="${window#*:}"
        else
            days="All"
            times="$window"
        fi

        # Check day match
        local day_match=0
        if [ "$days" = "All" ]; then
            day_match=1
        elif echo "$days" | grep -q "-"; then
            local start_day="${days%%-*}"
            local end_day="${days#*-}"
            local start_num=$(day_to_num "$start_day")
            local end_num=$(day_to_num "$end_day")

            if [ "$start_num" -le "$end_num" ]; then
                if [ "$curr_day_num" -ge "$start_num" ] && [ "$curr_day_num" -le "$end_num" ]; then
                    day_match=1
                fi
            else
                if [ "$curr_day_num" -ge "$start_num" ] || [ "$curr_day_num" -le "$end_num" ]; then
                    day_match=1
                fi
            fi
        else
            if [ "$curr_day" = "$days" ]; then
                day_match=1
            fi
        fi

        [ "$day_match" -eq 0 ] && continue

        # Parse time range (e.g. 05:00-23:00)
        # NOTE: %%-* would greedily strip too much (e.g. "05:00-23:00" -> "05")
        # Use cut to safely split on the hyphen separating HH:MM-HH:MM
        local start_t
        local end_t
        start_t=$(echo "$times" | cut -d'-' -f1)
        end_t=$(echo "$times" | cut -d'-' -f2)

        local sh="${start_t%%:*}"
        local sm="${start_t#*:}"
        local eh="${end_t%%:*}"
        local em="${end_t#*:}"

        [ -z "$sh" ] && sh=0
        [ -z "$sm" ] && sm=0
        [ -z "$eh" ] && eh=0
        [ -z "$em" ] && em=0

        local start_h=$((10#$sh))
        local start_m_part=$((10#$sm))
        local end_h=$((10#$eh))
        local end_m_part=$((10#$em))

        local start_m=$(( start_h * 60 + start_m_part ))
        local end_m=$(( end_h * 60 + end_m_part ))

        if [ "$end_m" -lt "$start_m" ]; then
            # Window spans midnight (e.g. 18:00-05:00)
            if [ "$curr_time_m" -ge "$start_m" ] || [ "$curr_time_m" -le "$end_m" ]; then
                return 0
            fi
        else
            # Normal window within same day (e.g. 05:00-23:00)
            if [ "$curr_time_m" -ge "$start_m" ] && [ "$curr_time_m" -le "$end_m" ]; then
                return 0
            fi
        fi
    done

    return 1
}
