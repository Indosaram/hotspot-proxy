#!/bin/bash
set -euo pipefail
[ "$EUID" -eq 0 ] || { echo "Run with sudo"; exit 1; }
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
launchctl bootout system/com.indo.hotspot-tun.watch 2>/dev/null || true
# Do not delete recovery state if restoration fails. The user can retry this command.
if [ -x /usr/local/libexec/hotspot-tun.sh ] && grep -q '^restore_dns()' /usr/local/libexec/hotspot-tun.sh; then
  /usr/local/libexec/hotspot-tun.sh --stop
elif [ -x /usr/local/libexec/hotspot-tun.sh ] && ! grep -q '^restore_dns()' /usr/local/libexec/hotspot-tun.sh; then
  legacy_dns=$(/usr/sbin/networksetup -getdnsservers Wi-Fi)
  if [ "$legacy_dns" = 172.19.0.2 ]; then
    echo "Old installation has no DNS backup. Restore your intended Wi-Fi DNS before uninstalling." >&2
    exit 1
  fi
elif [ -d /usr/local/var/hotspot-tun/dns-state ]; then
  echo "DNS recovery state exists but watcher is missing; restore it before uninstalling" >&2
  exit 1
fi
launchctl bootout system/com.indo.hotspot-tun.singbox 2>/dev/null || true
launchctl bootout system/com.indo.tailscaled 2>/dev/null || true
rm -f /Library/LaunchDaemons/com.indo.tailscaled.plist /usr/local/libexec/tailscaled-wrapper.sh
rm -f /Library/LaunchDaemons/com.indo.hotspot-tun.*.plist /usr/local/libexec/hotspot-tun.sh
rm -rf /usr/local/etc/hotspot-tun /usr/local/var/hotspot-tun
echo "Uninstalled; previous DNS configuration restored"
