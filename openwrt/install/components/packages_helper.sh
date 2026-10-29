#!/bin/sh

install_packages() {
    # etherwake: Wake-on-LAN magic packets
    # jsonfilter: JSON parsing for the Telegram bot
    # curl: Telegram/Discord notifications
    # (uhttpd/uhttpd-mod-ubus are intentionally NOT installed: this suite does
    #  not ship any CGI or web portal, so the web server is dead weight.)
    PACKAGES="etherwake jsonfilter curl"

    if command -v apk >/dev/null 2>&1; then
        echo "Modern OpenWrt (apk package manager) detected. Updating repository index..."
        apk update

        # apk handles package names natively.
        for pkg in $PACKAGES; do
            if ! apk info -e "$pkg" >/dev/null 2>&1; then
                echo "Installing $pkg..."
                apk add "$pkg"
            else
                echo "$pkg is already installed."
            fi
        done
    else
        echo "Traditional OpenWrt (opkg package manager) detected. Updating package list..."
        opkg update
        for pkg in $PACKAGES; do
            if ! opkg list-installed | grep -q "^$pkg[[:space:]]"; then
                echo "Installing $pkg..."
                opkg install "$pkg"
            else
                echo "$pkg is already installed."
            fi
        done
    fi
}
