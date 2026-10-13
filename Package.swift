// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CampusCat",
    platforms: [.macOS(.v12)],
    targets: [
        // Art and JSON live in Resources/ and are copied into the .app by
        // scripts/build_app.sh, so the target itself has no SwiftPM resources.
        .executableTarget(name: "CampusCat", path: "Sources/CampusCat")
    ]
)
