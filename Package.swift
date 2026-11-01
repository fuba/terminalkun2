// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TerminalKun2",
    platforms: [.iOS(.v17), .macOS(.v15)],
    products: [
        .library(name: "TerminalCore", targets: ["TerminalCore"]),
        .library(name: "TerminalTransport", targets: ["TerminalTransport"]),
        .library(name: "TerminalIME", targets: ["TerminalIME"]),
        .library(name: "TerminalRenderer", targets: ["TerminalRenderer"])
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.99.1", traits: []),
        .package(path: "Vendor/Citadel"),
        .package(url: "https://github.com/azooKey/AzooKeyKanaKanjiConverter", exact: "0.11.2", traits: [])
    ],
    targets: [
        .target(name: "TerminalCore"),
        .target(name: "TerminalTransport", dependencies: ["TerminalCore", .product(name: "Citadel", package: "Citadel")]),
        .target(name: "TerminalIME", dependencies: ["TerminalCore", .product(name: "KanaKanjiConverterModuleWithDefaultDictionary", package: "AzooKeyKanaKanjiConverter")]),
        .target(name: "TerminalRenderer", dependencies: [.product(name: "SwiftTerm", package: "SwiftTerm")]),
        .executableTarget(name: "SSHFixture", dependencies: [.product(name: "Citadel", package: "Citadel")], path: "Tools/SSHFixture"),
        .testTarget(name: "TerminalCoreTests", dependencies: ["TerminalCore"]),
        .testTarget(name: "TerminalTransportTests", dependencies: ["TerminalTransport"]),
        .testTarget(name: "TerminalIMETests", dependencies: ["TerminalIME"]),
        .testTarget(name: "TerminalRendererTests", dependencies: ["TerminalRenderer"])
    ],
    swiftLanguageModes: [.v5]
)
