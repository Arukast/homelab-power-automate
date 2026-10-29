#!/bin/sh

check_permission() {
    if [ ! -f "$SSH_KEY_PATH" ]; then
        echo "Error: SSH key not found at $SSH_KEY_PATH." >&2
        exit 1
    fi

    # Compare the FULL symbolic permission mode (-rw------- == 0600). An earlier
    # version checked owner bits only (ls -ld | cut -c 2-4), which let a
    # group/other-readable key (e.g. 0644) pass unnoticed. `stat -c` is avoided
    # because it is not reliably present/compatible on every OpenWrt build.
    perms=$(ls -l "$SSH_KEY_PATH" 2>/dev/null | awk '{print $1}')
    case "$perms" in
        -rw-------)
            # Correctly locked down.
            ;;
        *)
            echo "Warning: SSH key permissions are too open (found ${perms:-unknown}). Setting to 600..."
            chmod 600 "$SSH_KEY_PATH" 2>/dev/null
            ;;
    esac
}
