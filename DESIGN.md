# Hotspot Proxy Design System

Native SwiftUI (iOS 17+). Every color, type style, spacing value, and component below maps to a SwiftUI token. Views must not use raw hex values or arbitrary point sizes.

## 0. Research Log

- Embedded refs: shortlisted `apple`, `linear.app`, `raycast`. Picked `taste-skill` (operational utility app, restraint is correct) + `apple` (Layer B) because this is a single-purpose iOS utility that has to read as first-party. From `apple` we take neutral grouped canvases, one accent family used only for actions, capsule geometry for primary actions, tonal surfaces in place of borders, and SF Pro.
- Lazyweb / StyleGallery / Imagen drafts: skipped. This is a native iOS surface governed by Apple HIG plus system components (List, Form, WidgetKit families), so web layout grammar and bitmap concepts do not transfer. System Settings, Control Center, and the Personal Hotspot screen serve as the reference grammar.

## 1. Atmosphere & Identity

A quiet utility that feels like a missing piece of iOS. It looks like it ships with the phone: calm grouped surfaces, one confident teal signal, and nothing to configure until you go looking. The signature element is the **signal ring**, a status hero built from concentric broadcast arcs around the hotspot glyph. It is teal and gently breathing while the proxy serves, amber when the hotspot is off, and grey when stopped. The same ring appears on the app icon, the lock-screen circular widget, and the main screen, so the state is recognizable at a glance in all three places.

## 2. Color

Asset catalog `Shared/Colors.xcassets` (shared by app and widget). All colors adapt to light and dark mode.

| Role | Token (SwiftUI) | Light | Dark | Usage |
|---|---|---|---|---|
| Accent | `Color.accentColor` / `AccentColor` | #0B8A7D | #33D6C2 | Primary action fill, links, tint |
| Signal/on | `Color("SignalOn")` | #14A35A | #32D74B | "Serving" status dot, ring |
| Signal/warn | `Color("SignalWarn")` | #C76A00 | #FF9F0A | Hotspot off, port conflict |
| Signal/off | `Color("SignalOff")` | #8E8E93 | #8E8E93 | Stopped |
| Hero tint | `Color("HeroTint")` | #E3F4F1 | #0D2622 | Hero card wash while running |
| Widget bg | `WidgetBackground` | #FFFFFF | #0E1513 | Home widget container |
| Launch bg | `LaunchBackground` | #F2F5F4 | #000000 | Launch screen |
| Surfaces | `Color(.systemGroupedBackground)`, `.secondarySystemGroupedBackground` | system | system | Canvas and cards |
| Text | `.primary`, `.secondary`, `.tertiary` | system | system | All text |
| Error | `Color.red` (system) | system | system | Error text, destructive actions |

Rules:
- Accent appears only on the primary start/stop control, links, and tint. Status is shown with signal colors, never with accent.
- Status is never conveyed by color alone. Every state also has a symbol and a label.

## 3. Typography

SF Pro via Dynamic Type text styles only. Fixed point sizes are never used, so text scales with the user's setting.

| Level | SwiftUI | Usage |
|---|---|---|
| Hero value | `.largeTitle.weight(.semibold)` + `.monospacedDigit()` | IP:port on the hero |
| Title | `.title2.weight(.semibold)` | Status headline |
| Headline | `.headline` | Row titles, button labels |
| Body | `.body` | Default |
| Callout | `.callout` | Hero supporting line |
| Footnote | `.footnote` | Section footers, help |
| Caption | `.caption` / `.caption2` | Widget metadata, stat labels |
| Mono | `.system(.body, design: .monospaced)` | Addresses, ports, commands |

Rules: numbers use `.monospacedDigit()` so they don't jitter when they update. Widgets use `.minimumScaleFactor(0.6)` on endpoint text.

## 4. Spacing & Layout

Base unit is 4pt. Code references the `Space` enum in `Sources/Design/Tokens.swift`.

| Token | Value | Usage |
|---|---|---|
| `Space.xs` | 4 | icon to label |
| `Space.s` | 8 | inline groups |
| `Space.m` | 12 | stat tile padding |
| `Space.l` | 16 | card padding, screen margin |
| `Space.xl` | 24 | between hero blocks |
| `Space.xxl` | 32 | hero vertical padding |

Layout: a single column inside `ScrollView` + `VStack` on the main screen, and `Form` (inset grouped) in Settings. Portrait only, iPhone only. The scroll owner is the screen `ScrollView`/`Form`. There are no nested scrolls.

## 5. Components

Each component lives in `Sources/Design/Components.swift`.

### SignalRing
- **Structure**: ZStack of 3 concentric arcs plus the `personalhotspot` SF Symbol at the center.
- **Variants**: `.running` (SignalOn, arcs pulse outward), `.noHotspot` (SignalWarn, static), `.stopped` (SignalOff, 30% opacity arcs), `.error` (red, `exclamationmark` glyph).
- **Motion**: arcs scale 0.9 to 1.05 and fade over 2.4s repeating only while running. Under reduced motion they are static at full opacity.
- **Accessibility**: decorative (`accessibilityHidden`). The status label carries the meaning.

### StatusHero (card)
- **Structure**: SignalRing, status title, endpoint (IP:port, mono, large), copy button, supporting line.
- **States**: running, noHotspot (endpoint replaced by "Turn On Personal Hotspot" and a button that opens Settings), stopped, error (message + retry).
- **Surface**: `secondarySystemGroupedBackground`, radius `Radius.card` (22), with a HeroTint wash while running.
- **Accessibility**: the combined element reads "Proxy Running, Proxy address 172.20.10.1 port 8080". The copy button is labeled "Copy address".

### PowerButton (primary action)
- **Structure**: full-width capsule, 56pt high, with a symbol and label ("Start Proxy" / "Stop Proxy").
- **Variants**: start = accent fill with white label; stop = `.secondarySystemFill` fill with primary label.
- **States**: pressed (scale 0.97, 120ms), disabled (opacity 0.4). A success haptic plays on start and a light haptic on stop.

### StatTile
- **Structure**: VStack with an SF Symbol, a value (`.title3` mono digits), and a caption label.
- **Usage**: a 3-up grid of active connections, transferred bytes, and uptime.
- **Motion**: the value uses `.contentTransition(.numericText())`.

### CopyableRow
- LabeledContent with mono value plus a trailing copy button. Copying plays a haptic and swaps the symbol to a checkmark for 1.5s.

### SetupStep (onboarding / Mac guide)
- Numbered circle, title, and body. Used in onboarding and in the "Connect Other Devices" screen.

## 6. Motion & Interaction

| Type | Duration | Curve | Usage |
|---|---|---|---|
| Micro | 120ms | `.snappy` | button press, copy check |
| Standard | 300ms | `.smooth` | state change of hero, tint wash |
| Ambient | 2.4s repeat | `.easeInOut` | SignalRing pulse (running only) |

- Haptics use `.sensoryFeedback`: `.success` on start, `.impact(weight: .light)` on stop and copy, `.error` on failure.
- `@Environment(\.accessibilityReduceMotion)` disables the ring pulse.
- When the app is hidden, fast UI polling stops. A slower heartbeat renews the widget observation and checks the hotspot address.

## 7. Depth & Surface

The strategy is tonal shift: grouped canvas plus secondary cards, with no borders and no custom shadows.

| Token | Value | Usage |
|---|---|---|
| `Radius.card` | 22 | hero card |
| `Radius.tile` | 16 | stat tiles (concentric: 22 - padding 6) |
| `Radius.capsule` | Capsule() | primary action |

## 8. Accessibility Constraints & Accepted Debt

Constraints:
- Dynamic Type up to AX5. Stat tiles reflow from 3-up to a vertical stack at accessibility sizes.
- VoiceOver labels exist on all controls. Status is announced by text, never by color.
- Text contrast meets WCAG AA in both appearances. Hit targets are 44pt minimum.
- Reduced motion is respected (see Section 6).

Accepted debt:
| Item | Location | Why accepted | Exit |
|---|---|---|---|
| English-only UI strings | all views | The UI ships in English only (user requirement). Strings are inline literals, so a String Catalog can be extracted later. | Add `Localizable.xcstrings` if another locale is needed |
| Widget refresh timing is controlled by iOS | Widget | Heartbeats renew observations; a scheduled expiry shows Unverified after two minutes | Verify timing on device |
