#!/bin/bash
# Usage: sudo bash install.sh   (once)
set -euo pipefail
cd "$(dirname "$0")"
[ "$EUID" -eq 0 ] || { echo "Run as: sudo bash install.sh"; exit 1; }
# Kernel advisory lock; retained across exec and shared by nested lifecycle commands.
# Keep this inode outside the removable installation state directory.
mkdir -p /usr/local/var || exit 1
if [ "${HOTSPOT_LOCK_PID:-}" != "$$" ]; then
  exec /usr/bin/perl -MFcntl=:flock,F_SETFD -e '
    my $path = shift @ARGV;
    my $lock;
    if (defined($ENV{HOTSPOT_LOCK_FD}) && $ENV{HOTSPOT_LOCK_FD} =~ /^\d+$/) {
      if (open(my $inherited, ">&=" . $ENV{HOTSPOT_LOCK_FD})) {
        my @held = stat($inherited); my @current = stat($path);
        $lock = $inherited if @held && @current && $held[0] == $current[0] && $held[1] == $current[1];
      }
    }
    if (!defined($lock)) { open($lock, ">>", $path) or die "Cannot open lifecycle lock: $!\n"; }
    flock($lock, LOCK_EX | LOCK_NB) or die "Lifecycle operation already running; retry shortly\n";
    fcntl($lock, F_SETFD, 0) or die "Cannot retain lifecycle lock: $!\n";
    $ENV{HOTSPOT_LOCK_PID} = $$;
    $ENV{HOTSPOT_LOCK_FD} = fileno($lock);
    exec "/bin/bash", @ARGV;
    die "Cannot start locked operation: $!\n";
  ' /usr/local/var/hotspot-tun.lock "$0" "$@"
fi
# Validate before replacing a working installation. Homebrew may use either prefix.
SINGBOX=$(command -v sing-box || true)
if [ -z "$SINGBOX" ]; then
  for candidate in /opt/homebrew/bin/sing-box /usr/local/bin/sing-box; do
    if [ -x "$candidate" ]; then SINGBOX="$candidate"; break; fi
  done
fi
[ -n "$SINGBOX" ] || { echo "Install sing-box first" >&2; exit 1; }
"$SINGBOX" check -c config.json
if [ -x /usr/local/libexec/hotspot-tun.sh ] && ! grep -q '^restore_dns()' /usr/local/libexec/hotspot-tun.sh; then
  legacy_dns=$(/usr/sbin/networksetup -getdnsservers Wi-Fi)
  if [ "$legacy_dns" = 172.19.0.2 ]; then
    echo "Old installation has no DNS backup. Restore your intended Wi-Fi DNS before upgrading." >&2
    exit 1
  fi
fi
launchctl bootout system/com.indo.hotspot-tun.watch 2>/dev/null || true
if [ -x /usr/local/libexec/hotspot-tun.sh ] && grep -q '^restore_dns()' /usr/local/libexec/hotspot-tun.sh; then
  /usr/local/libexec/hotspot-tun.sh --stop
fi
mkdir -p /usr/local/etc/hotspot-tun /usr/local/var/hotspot-tun /usr/local/libexec
install -m 644 config.json /usr/local/etc/hotspot-tun/config.json
install -m 755 hotspot-tun.sh /usr/local/libexec/hotspot-tun.sh
install -m 644 com.indo.hotspot-tun.singbox.plist /Library/LaunchDaemons/
/usr/libexec/PlistBuddy -c "Set :ProgramArguments:0 $SINGBOX" /Library/LaunchDaemons/com.indo.hotspot-tun.singbox.plist
install -m 644 com.indo.hotspot-tun.watch.plist /Library/LaunchDaemons/
launchctl bootout system/com.indo.hotspot-tun.watch 2>/dev/null || true
launchctl bootout system/com.indo.hotspot-tun.singbox 2>/dev/null || true
launchctl bootstrap system /Library/LaunchDaemons/com.indo.hotspot-tun.watch.plist
sleep 3
launchctl print system/com.indo.hotspot-tun.singbox >/dev/null 2>&1 && echo "TUN on" || echo "Standing by (TUN stays off until the hotspot and proxy app are reachable)"
