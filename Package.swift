// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NavbarMonit",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "NavbarMonit",
            path: "Sources/NavbarMonit"
        )
    ]
)
