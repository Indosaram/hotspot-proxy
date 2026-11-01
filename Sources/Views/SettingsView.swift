import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var m: ProxyModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @State private var portText = ""
    @FocusState private var portFocused: Bool

    private var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "–"
        let b = info?["CFBundleVersion"] as? String ?? "–"
        return "\(v) (\(b))"
    }

    private var portValid: Bool { Int(portText).map { (1024...65535).contains($0) } ?? false }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Port") {
                        TextField("8080", text: $portText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .focused($portFocused)
                            .foregroundStyle(portValid || portText.isEmpty ? Color.primary : Color.red)
                            .onSubmit(commitPort)
                            .accessibilityLabel("Port number")
                    }
                    .disabled(m.requested || m.running)
                    Toggle("Start on Launch", isOn: $m.autoStart)
                } header: {
                    Text("Proxy")
                } footer: {
                    if m.requested || m.running {
                        Text("Stop the proxy to change the port.")
                    } else if !portValid && !portText.isEmpty {
                        Text("Enter a number between 1024 and 65535.").foregroundStyle(.red)
                    } else {
                        Text("HTTP, HTTPS, and SOCKS5 all share this port.")
                    }
                }

                Section {
                    if m.addresses.isEmpty {
                        Text("No active network interfaces").foregroundStyle(.secondary)
                    }
                    ForEach(Array(m.addresses.enumerated()), id: \.offset) { _, a in
                        CopyableRow(title: a.0.hasPrefix("bridge") ? "\(a.0) · Hotspot" : a.0, value: a.1)
                    }
                } header: {
                    Text("Network Interfaces")
                } footer: {
                    Text("Interfaces starting with “bridge” are your Personal Hotspot. Other devices connect to that address.")
                }

                Section("Help") {
                    NavigationLink { ConnectGuideView() } label: {
                        Label("Connect Other Devices", systemImage: "laptopcomputer.and.iphone")
                    }
                    NavigationLink { MacSetupView() } label: {
                        Label("Mac Auto-Connect (TUN)", systemImage: "macbook")
                    }
                    Button {
                        hasOnboarded = false
                        dismiss()
                    } label: {
                        Label("Show Welcome Again", systemImage: "sparkles")
                    }
                }

                Section {
                    LabeledContent("Version", value: version)
                    Link(destination: URL(string: "https://github.com/Indosaram/hotspot-proxy")!) {
                        Label("GitHub Repository", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                } header: {
                    Text("About")
                } footer: {
                    Text("To keep the proxy running in the background, the app plays silent audio. It stops when you stop the proxy.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { commitPort(); dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Apply") { commitPort(); portFocused = false }
                }
            }
            .onAppear { portText = String(m.port) }
        }
    }

    private func commitPort() {
        guard let v = Int(portText), m.setPort(v) else {
            if !portValid { portText = String(m.port) }
            return
        }
    }
}
