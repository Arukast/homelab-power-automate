#!/bin/sh

verify_ssh() {
    echo "Verifying SSH connection and security wrapper on Proxmox (${HOST_SSH_USER}@${HOST_IP}:${HOST_SSH_PORT})..."
}

ssh_cmd() {
    # NOTE: OpenWrt's `ssh` is Dropbear's client, which rejects OpenSSH-style
    # `-o ConnectTimeout=...` ("Ignoring unknown configuration option"). The
    # connect-time bound for liveness probes is applied with BusyBox `timeout`
    # in check_helper.sh instead.
    ssh -p "$HOST_SSH_PORT" -i "$SSH_KEY_PATH" -y -K 3 "${HOST_SSH_USER}@$HOST_IP" "$1"
}

ssh_test() {
    SSH_TEST_OUTPUT=$(ssh_cmd 'echo OK' 2>&1)
    # Accept a bare "OK" line even if Dropbear emitted a warning on stderr
    # (stderr is merged in above for diagnostics), so a harmless notice cannot
    # be mistaken for a trust failure.
    if ! printf '%s\n' "$SSH_TEST_OUTPUT" | grep -qx 'OK'; then
        echo "Error: Cannot establish passwordless SSH trust. SSH command failed." >&2
        echo "SSH Output / Error:" >&2
        echo "----------------------------------------------------" >&2
        echo "$SSH_TEST_OUTPUT" >&2
        echo "----------------------------------------------------" >&2
        echo "Troubleshooting steps:" >&2
        echo "1. Verify Dropbear public key is in Proxmox /root/.ssh/authorized_keys (or ~${HOST_SSH_USER}/.ssh/authorized_keys):" >&2
        echo "   Run on OpenWrt: dropbearkey -y -f $SSH_KEY_PATH" >&2
        echo "2. Check Proxmox firewall/port: nc -z -w 3 $HOST_IP $HOST_SSH_PORT" >&2
        echo "3. Test manual SSH with verbose flag: ssh -v -p $HOST_SSH_PORT -i $SSH_KEY_PATH ${HOST_SSH_USER}@$HOST_IP" >&2
        exit 1
    fi
    echo "Passwordless SSH trust verified."
}

ssh_block() {
    if echo "$(ssh_cmd 'uname' 2>&1)" | grep -iq "Access Denied"; then
        echo "SSH Command Wrapper detected and active on Proxmox."
        WRAPPER_ACTIVE=1
    else
        echo "WARNING: SSH command restrictions NOT detected on Proxmox!"
        echo "The host executed 'uname' without wrapper blocking. This is a security risk."
        echo "Please prepend the command wrapper inside Proxmox /root/.ssh/authorized_keys."
        WRAPPER_ACTIVE=0
    fi
}
