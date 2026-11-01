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
                Text("HTTP, HTTPS, and SOCKS5 all use the same server and port.")
            }

            Section("iPhone · iPad") {
                SetupStep(number: 1, title: "Join the Hotspot", detail: "In Settings › Wi-Fi, choose this iPhone’s hotspot.")
                SetupStep(number: 2, title: "Open Network Info", detail: "Tap the (i) button next to the joined network.")
                SetupStep(number: 3, title: "Configure Proxy › Manual", detail: "Enter the server and port above, then Save.")
            }
            Section("macOS") {
                SetupStep(number: 1, title: "System Settings › Network › Wi-Fi", detail: "Click ‘Details…’ on the joined hotspot.")
                SetupStep(number: 2, title: "Proxies Tab", detail: "Enable Web (HTTP), Secure Web (HTTPS), and SOCKS proxies with the server and port.")
                SetupStep(number: 3, title: "Or Use Auto TUN", detail: "To route every app automatically, follow the ‘Mac Auto-Connect’ guide.")
            }
            Section("Android") {
                SetupStep(number: 1, title: "Long-Press the Wi-Fi Network", detail: "Modify network › Advanced options › Proxy › Manual.")
                SetupStep(number: 2, title: "Enter Host and Port", detail: "Use the server and port above, then Save.")
            }
            Section("Windows") {
                SetupStep(number: 1, title: "Settings › Network & Internet › Proxy", detail: "Under Manual proxy setup, turn on Use a proxy server.")
                SetupStep(number: 2, title: "Enter Address and Port", detail: "Use the server and port above, then Save.")
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
        ("Switch Tailscale to CLI (optional)", "sudo bash mac/install-tailscale.sh"),
    ]

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Space.s) {
                    Label("How It Works", systemImage: "bolt.horizontal.circle")
                        .font(.headline)
                    Text("When your Mac joins the iPhone hotspot (172.20.10.x) and this app’s proxy (172.20.10.1:8080) responds, a sing-box TUN turns on and sends all traffic through the proxy. Leave the hotspot and it turns off and restores your previous DNS settings.")
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
                Text("Run from the repository root. It re-checks on every network change and every 30 seconds.")
            }
        }
        .navigationTitle("Mac Auto-Connect")
        .navigationBarTitleDisplayMode(.inline)
    }
}
