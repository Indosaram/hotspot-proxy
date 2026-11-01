#!/bin/bash
# launchd watcher. DNS is changed only after the TUN answers DNS, and restored exactly.
set -u
export LC_ALL=C
LABEL=com.indo.hotspot-tun.singbox
PLIST=/Library/LaunchDaemons/$LABEL.plist
STATE=/usr/local/var/hotspot-tun
TUN_DNS=172.19.0.2
TUN=utun199
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
mkdir -p "$STATE" || exit 1
chmod 700 "$STATE" || exit 1

registered() { /bin/launchctl print "system/$LABEL" >/dev/null 2>&1; }
hotspot_device() {
  /sbin/ifconfig | awk '/^[^[:space:]].*:/{dev=$1;sub(/:$/, "", dev)} /inet 172\.20\.10\./ {print dev; exit}'
}
service_for_device() {
  /usr/sbin/networksetup -listnetworkserviceorder | awk -v device="$1" '
    /^\([0-9]+\) / {service=$0; sub(/^\([0-9]+\) /,"",service)}
    /Device: / {line=$0; sub(/^.*Device: /,"",line); sub(/\).*$/,"",line); if(line==device){print service;exit}}'
}
proxy_up() { /usr/bin/nc -z -G 2 172.20.10.1 8080 >/dev/null 2>&1; }
tun_ready() {
  /bin/launchctl print "system/$LABEL" 2>/dev/null | grep -q 'state = running' &&
    /sbin/ifconfig "$TUN" >/dev/null 2>&1 &&
    /usr/bin/dig @"$TUN_DNS" . NS +time=2 +tries=1 2>/dev/null | grep -q 'status: NOERROR'
}
restore_dns() {
  [ -d "$STATE/dns-state" ] || return 0
  local service current
  service=$(cat "$STATE/dns-state/service") || return 1
  current=$(/usr/sbin/networksetup -getdnsservers "$service") || return 1
  if [ "$current" = "$TUN_DNS" ]; then
    local servers=() value
    while IFS= read -r value; do servers+=("$value"); done < "$STATE/dns-state/servers"
    [ "${#servers[@]}" -gt 0 ] || return 1
    /usr/sbin/networksetup -setdnsservers "$service" "${servers[@]}" || return 1
    current=$(/usr/sbin/networksetup -getdnsservers "$service") || return 1
    if [ "${servers[0]}" = Empty ]; then
      case "$current" in "There aren't any DNS Servers set on "*) ;; *) return 1 ;; esac
    else
      [ "$current" = "$(cat "$STATE/dns-state/servers")" ] || return 1
    fi
  fi
  # If the user changed DNS in the meantime, preserve their newer setting.
  rm -rf "$STATE/dns-state"
}
activate_dns() {
  local service="$1" current saved
  if [ -d "$STATE/dns-state" ]; then
    saved=$(cat "$STATE/dns-state/service") || return 1
    [ "$saved" = "$service" ] || restore_dns || return 1
  fi
  current=$(/usr/sbin/networksetup -getdnsservers "$service") || return 1
  if [ -d "$STATE/dns-state" ] && [ "$current" = "$TUN_DNS" ]; then return 0; fi
  # Refresh the backup if the user changed DNS while active.
  [ ! -d "$STATE/dns-state" ] || restore_dns || return 1
  if [ "$current" = "$TUN_DNS" ]; then
    echo "TUN DNS has no saved original configuration; restore DNS manually before enabling" >&2
    return 1
  fi
  rm -rf "$STATE/dns-pending"
  mkdir -m 700 "$STATE/dns-pending" || return 1
  printf '%s\n' "$service" > "$STATE/dns-pending/service" || return 1
  case "$current" in
    "There aren't any DNS Servers set on "*) printf '%s\n' Empty > "$STATE/dns-pending/servers" ;;
    '') return 1 ;;
    *) printf '%s\n' "$current" > "$STATE/dns-pending/servers" ;;
  esac || return 1
  mv "$STATE/dns-pending" "$STATE/dns-state" || return 1
  /usr/sbin/networksetup -setdnsservers "$service" "$TUN_DNS" || return 1
  current=$(/usr/sbin/networksetup -getdnsservers "$service") || return 1
  [ "$current" = "$TUN_DNS" ]
}
stop_tun() {
  # Preserve the backup and the working TUN if restoration fails; retry next time.
  restore_dns || return 1
  if registered; then /bin/launchctl bootout "system/$LABEL" || return 1; fi
}

MODE=normal
if [ "${1:-}" = --stop ]; then
  stop_tun || exit 1
else
  device=$(hotspot_device)
  service=""
  if [ -n "$device" ]; then service=$(service_for_device "$device"); fi
  if [ -n "$service" ] && proxy_up; then
    # A registered job may have crashed. Require actual health on every run.
    if ! registered; then
      if ! /bin/launchctl bootstrap system "$PLIST"; then stop_tun; exit 1; fi
    fi
    ready=false
    for attempt in 1 2 3; do
      if tun_ready; then ready=true; break; fi
      /bin/sleep 1
    done
    if "$ready" && activate_dns "$service"; then
      MODE=hotspot
    else
      stop_tun || exit 1
    fi
  else
    stop_tun || exit 1
  fi
fi
MODE_FILE="$STATE/mode"
if [ "$(cat "$MODE_FILE" 2>/dev/null)" != "$MODE" ]; then
  printf '%s\n' "$MODE" > "$MODE_FILE"
  if /bin/launchctl print system/com.indo.tailscaled >/dev/null 2>&1; then
    /bin/launchctl kickstart -k system/com.indo.tailscaled
  fi
fi
