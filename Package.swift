// swift-tools-version: 5.9
import PackageDescription

var sources = ["Shared/ProxyProtocol.swift", "Shared/ProxySnapshot.swift"]
var excludes = ["Tests", "Widget", "Config", "Resources", "mac", "design", "docs", "HotspotProxy.xcodeproj", "README.md", "DESIGN.md", "project.yml", "Shared/Colors.xcassets", "Shared/StatusStyle.swift"]
#if os(macOS)
sources += ["Sources/ProxyServer.swift", "Sources/UdpRelay.swift"]
excludes += ["Sources/App.swift", "Sources/KeepAlive.swift", "Sources/Info.plist", "Sources/Design", "Sources/Model", "Sources/Views"]
#else
excludes += ["Sources"]
#endif
let package = Package(
    name: "HotspotProxyCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    targets: [
        .target(name: "ProxyCore", path: ".", exclude: excludes, sources: sources),
        .testTarget(name: "ProxyCoreTests", dependencies: ["ProxyCore"], path: "Tests/ProxyCoreTests")
    ]
)
