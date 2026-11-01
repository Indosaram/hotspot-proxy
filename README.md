<p align="center">
  <img src="design/icon/preview.png" width="420" alt="Hotspot Proxy app icon in light, dark, and tinted variants">
</p>

<h1 align="center">Hotspot Proxy</h1>

<p align="center">
  An iOS app that lets devices on your iPhone's Personal Hotspot use <b>the iPhone's own cellular connection as a proxy</b>.<br>
  HTTP, HTTPS (CONNECT), and SOCKS5 share a TCP port; SOCKS5 UDP uses a negotiated relay port.
</p>

<p align="center">
  <img alt="iOS 17+" src="https://img.shields.io/badge/iOS-17%2B-0B8A7D">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-5-F05138">
  <img alt="SwiftUI + WidgetKit" src="https://img.shields.io/badge/SwiftUI-WidgetKit-33D6C2">
</p>

---

## Why

Some carriers and plans classify tethered hotspot traffic separately and throttle or cap it. Hotspot Proxy runs a proxy server inside the iPhone. When devices on the hotspot (Mac, iPad, laptop) go through it, their traffic leaves as the iPhone app's own traffic.

## Screenshots

| Main (running) | Hotspot off | Settings | Welcome |
|---|---|---|---|
| <img src="docs/screenshots/main-light.png" width="200"> | <img src="docs/screenshots/nohotspot-light.png" width="200"> | <img src="docs/screenshots/settings-light.png" width="200"> | <img src="docs/screenshots/onboarding-light.png" width="200"> |
| <img src="docs/screenshots/main-dark.png" width="200"> | <img src="docs/screenshots/nohotspot-dark.png" width="200"> | <img src="docs/screenshots/settings-dark.png" width="200"> | <img src="docs/screenshots/onboarding-dark.png" width="200"> |

<img src="docs/screenshots/home-icon.png" width="300" alt="App icon on the Home Screen">

### Lock Screen and Home Screen widgets

<img src="docs/screenshots/widgets.png" width="420" alt="Lock Screen circular, rectangular, and inline widgets plus the small Home Screen widget">

- **Lock Screen** has three widgets:
  - Circular shows the status and connection count.
  - Rectangular shows the status, `IP:port`, connections, and data transferred.
  - Inline shows a one-line status.
- **Home Screen** has a small widget with a status chip, the proxy address, stats, and when it last updated.
- Tapping a widget opens the app. The app reloads widgets on state changes and with a bounded heartbeat; stale observations become Unverified.

## Features

- **Status hero.** A "signal ring" shows the current state: green while running, amber when the hotspot is off, grey when stopped, and red on error.
- **One-tap start and stop**, with haptic feedback.
- **Copy the address.** One tap copies `172.20.10.1:8080` to enter on other devices.
- **Live stats** for active connections, data transferred, and uptime. UI stats refresh while visible, with a slower background heartbeat for shared state.
- **Connection guides** for iPhone/iPad, macOS, Android, and Windows.
- **Mac auto-TUN guide.** The `mac/` scripts optionally route traffic through a TUN, with explicit bypasses and DNS recovery.
- **Welcome flow** that covers turning on the hotspot, local network permission, and how background keep-alive works.
- **Accessibility:** Dark Mode, Dynamic Type (including accessibility sizes), VoiceOver labels, and Reduce Motion.

## Usage

1. On the iPhone, turn on **Settings › Personal Hotspot › Allow Others to Join**.
2. Open the app and tap **Start Proxy**. By default it starts automatically on launch.
3. Join the hotspot from another device and use the **current server IP and port shown in the app** (defaults: `172.20.10.1`, `8080`).
4. Configure HTTP/HTTPS or an application's SOCKS5 proxy as described in the platform guide. No proxy authentication is supported.

### Platform setup guides · 한국어

- **[macOS: manual HTTP/HTTPS, SOCKS5, optional TUN, and DNS recovery](docs/macos.md)**
- **[Windows 11 / 10: manual proxy, application limitations, and restoration](docs/windows.md)**

Both guides include iPhone prerequisites, connection checks, disabling/restoring settings, and troubleshooting. OS proxy settings apply to applications that honor them; they do not force all traffic or UDP through the proxy. SOCKS5 UDP requires a compatible client using the negotiated UDP port while keeping its TCP control connection open.

### Mac TUN automation (optional)

Read the [Mac guide](docs/macos.md) before installing. The scripts require the default `172.20.10.1:8080` endpoint and a Mac interface on `172.20.10.x`; they do not discover a changed app port. The watcher checks network configuration changes and every 30 seconds, applies DNS only after TUN health checks, and saves the previous DNS for restoration. Private routes and configured exclusions bypass the proxy; this is not a guarantee that all system traffic is proxied. There is no Windows TUN installer in this repository.

## Background behavior and battery

iOS doesn't keep a background app's sockets alive for long. To stay running, the app loops **silent audio** (8 kHz, in 30-second segments). The audio mixes with other apps (`mixWithOthers`) at zero volume. UI polling runs only while the screen is visible, with a slower background heartbeat for network state and widgets, and idle UDP destinations are cleaned up after 60 seconds.

> The silent-audio background mode may not pass App Store review. This app is intended for personal sideloading or developer-signed builds.

## Build

```bash
brew install xcodegen
xcodegen generate
open HotspotProxy.xcodeproj
```

- The project has three targets: `HotspotProxy` (app), `HotspotProxyWidget` (WidgetKit extension), and `HotspotProxyTests` (hosted iOS tests).
- The targets share state through the App Group `group.com.indoyoon.hotspotproxy`. To build under your own team, change `DEVELOPMENT_TEAM`, the bundle IDs, and the App Group in `project.yml`.
- Icon sources are in `design/icon/*.svg`. The design system is in [`DESIGN.md`](DESIGN.md).

## Layout

```
Sources/
  App.swift              App entry, deep-link handling
  Model/ProxyModel.swift Proxy state, widget snapshot publishing
  Views/                 Main, settings, welcome, connection guide, Mac guide
  Design/                Tokens and shared components (SignalRing, StatusHero, ...)
  ProxyServer.swift      HTTP/CONNECT + SOCKS5 server (Network.framework)
  UdpRelay.swift         SOCKS5 UDP ASSOCIATE relay
  KeepAlive.swift        Silent-audio background keep-alive
Widget/                  Lock Screen and Home Screen widgets
Shared/                  App/widget shared snapshot, deep links, color assets
mac/                     macOS sing-box TUN automation scripts
```

## Deep links

| URL | Action |
|---|---|
| `hotspotproxy://open` | Open the app |
| `hotspotproxy://start` / `stop` / `toggle` | Control the proxy |
| `hotspotproxy://copy` | Copy the proxy address |

Use the "Open URLs" action in Shortcuts to automate them.

## Safety and lifecycle

The app listens only on the active Personal Hotspot bridge address. It does not
open a proxy on ordinary Wi-Fi interfaces. Without a hotspot it waits for one;
if iOS has suspended the waiting app, open it after enabling Personal Hotspot.
Clients on the hotspot are trusted (there is no password authentication).
HTTP URLs retain their original escaped paths and invalid ports are rejected.

TCP sessions are limited to 128, with a 15-second initial handshake deadline.
SOCKS5 only accepts clients that offer the no-auth method. UDP ASSOCIATE creates
a dedicated ephemeral UDP port on the same local address, returns an IPv4 or
IPv6 reply as appropriate, and closes that port with its TCP control connection.
Clients must use the returned port. The relay accepts only the TCP peer's IP and
requested UDP source port (or pins the first port when zero was requested).
Each association is limited to 64 destination sockets; individual destinations
expire after 60 seconds without traffic, even when other destinations are busy.

Widgets show a recent observation, not an independent health check. The app
publishes a heartbeat while running; after two minutes without a fresh observation,
a scheduled timeline entry changes to **Unverified**. iOS controls widget update
timing and may show Unverified while a healthy app is awaiting its next refresh.

Mac automation discovers the network service attached to the hotspot interface
(including USB or renamed services). It changes DNS only after the sing-box process,
TUN interface and a DNS query through the TUN are healthy. It saves and restores the
original DNS list, preserves a user's newer changes, and retains recovery state if
restoration fails. The watcher uses macOS system Perl for an OS advisory lock, which releases automatically on process exit or crash. Retry uninstall if it reports a restore or watcher-lock failure.
If an older installation already left `172.19.0.2` configured without a DNS backup,
restore the intended DNS manually first; the original setting cannot be inferred.
The default Mac configuration still uses `172.20.10.1:8080`; changing the app port
requires updating both the Mac configuration and watcher probe.

## Tests

```bash
swift test                                      # portable parser/state tests
python3 -m unittest discover -s Tests/mac -v     # mocked OS commands; no sudo/network changes
```

On macOS, `swift test` also compiles the production Network.framework proxy and
runs loopback integration tests for negotiation, malformed HTTP, deadlines,
IPv6 UDP replies and TCP/UDP association cleanup. The GitHub workflow additionally
builds the app and widget and runs hosted tests in the iOS simulator. The tests do not install launchd
jobs or change host DNS. Simulator builds do not verify Personal Hotspot routing,
background audio, physical-device permission prompts, or live Mac TUN transitions;
those need a device and a macOS smoke test before release.
