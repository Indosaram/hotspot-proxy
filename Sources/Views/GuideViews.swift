import SwiftUI

struct ConnectGuideView: View {
    @EnvironmentObject var m: ProxyModel

    var body: some View {
        List {
            Section {
                if let ip = m.hotspotIP {
                    CopyableRow(title: "Server", value: ip)
                } else {
                    LabeledContent("Server", value: "Hotspot off (usually 172.20.10.1)")
                }
                CopyableRow(title: "Port", value: String(m.port))
            } header: {
                Text("Values to Enter")
            } footer: {
                Text("HTTP, HTTPS CONNECT, and SOCKS5 share this TCP endpoint. SOCKS5 UDP uses a separately negotiated port. Only proxy-aware apps follow manual settings.")
            }

            Section("iPhone · iPad") {
                SetupStep(number: 1, title: "Join the Hotspot", detail: "In Settings › Wi-Fi, choose this iPhone’s hotspot.")
                SetupStep(number: 2, title: "Open Network Info", detail: "Tap the (i) button next to the joined network.")
                SetupStep(number: 3, title: "Configure Proxy › Manual", detail: "Enter the server and port above, then Save.")
            }
            Section("macOS") {
                SetupStep(number: 1, title: "System Settings › Network › Wi-Fi", detail: "Click ‘Details…’ on the joined hotspot.")
                SetupStep(number: 2, title: "Proxies Tab", detail: "Enable Web (HTTP) and Secure Web (HTTPS) with the values above; leave authentication off. Configure SOCKS5 separately for apps that support it.")
                SetupStep(number: 3, title: "Optional Auto TUN", detail: "For optional TUN routing with bypasses and DNS recovery, read ‘Mac Auto-Connect’. It requires 172.20.10.1:8080.")
                SetupStep(number: 4, title: "Restore When Finished", detail: "Turn off the proxies you enabled and restore any previous proxy/PAC settings before leaving the hotspot.")
            }
            Section("Android") {
                SetupStep(number: 1, title: "Long-Press the Wi-Fi Network", detail: "Modify network › Advanced options › Proxy › Manual.")
                SetupStep(number: 2, title: "Enter Host and Port", detail: "Use the server and port above, then Save.")
            }
            Section("Windows") {
                SetupStep(number: 1, title: "Settings › Network & Internet › Proxy", detail: "Under Manual proxy setup, turn on Use a proxy server.")
                SetupStep(number: 2, title: "Enter Address and Port", detail: "Use the server and port above without authentication, then Save. This applies only to apps that honor Windows proxy settings.")
                SetupStep(number: 3, title: "Restore When Finished", detail: "Turn off Use a proxy server or restore your previous settings before leaving the hotspot. App-specific SOCKS settings must be restored separately.")
            }
        }
        .navigationTitle("Connect Devices")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MacSetupView: View {
    private let commands: [(String, String)] = [
        ("Install sing-box", "brew install sing-box"),
        ("Install auto TUN", "sudo bash mac/install.sh"),
        ("Uninstall", "sudo bash mac/uninstall.sh"),
    ]

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Space.s) {
                    Label("How It Works", systemImage: "bolt.horizontal.circle")
                        .font(.headline)
                    Text("When your Mac joins the iPhone hotspot (172.20.10.x) and this app’s proxy (172.20.10.1:8080) responds, a sing-box TUN routes captured traffic through the proxy, with private-network bypasses. DNS changes only after health checks. Leaving the hotspot triggers restoration of saved DNS; failures require recovery. This is not a guarantee that every app or IPv6 traffic is proxied.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, Space.xs)
            }
            Section {
                ForEach(commands, id: \.1) { c in
                    CopyableRow(title: c.0, value: c.1)
                }
            } header: {
                Text("Terminal Commands")
            } footer: {
                Text("Read docs/macos.md in the repository before installing. Run from the repository root. Checks run on network configuration changes and every 30 seconds. A custom app port requires script changes. Uninstall restores DNS; manual proxy settings must be restored separately.")
            }
        }
        .navigationTitle("Mac Auto-Connect")
        .navigationBarTitleDisplayMode(.inline)
    }
}
