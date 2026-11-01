#!/bin/bash
# Usage: sudo bash mac/install-tailscale.sh  (once)
# Replaces the GUI Tailscale app with the CLI tailscaled as a launchd service.
set -euo pipefail
cd "$(dirname "$0")"
[ "$EUID" -eq 0 ] || { echo "Run with sudo"; exit 1; }
osascript -e 'quit app "Tailscale"' 2>/dev/null || true
pkill -x Tailscale 2>/dev/null || true
pkill -x tailscaled 2>/dev/null || true
sleep 2
install -m 755 tailscaled-wrapper.sh /usr/local/libexec/tailscaled-wrapper.sh
# The watcher and DNS recovery state are owned by install.sh.
[ -x /usr/local/libexec/hotspot-tun.sh ] || { echo "Run mac/install.sh first" >&2; exit 1; }
install -m 644 com.indo.tailscaled.plist /Library/LaunchDaemons/
launchctl bootout system/com.indo.tailscaled 2>/dev/null || true
launchctl bootstrap system /Library/LaunchDaemons/com.indo.tailscaled.plist
sleep 5
/opt/homebrew/bin/tailscale up 2>&1 | tail -2 || true
/opt/homebrew/bin/tailscale status | head -3
