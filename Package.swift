// swift-tools-version:5.9
import PackageDescription

// Mac command-line build (bundle.sh, --snapshot, --import …). The iOS app is built from Lexikos.xcodeproj (project.yml).
let package = Package(
    name: "Lexikos",
    platforms: [.macOS(.v14)],
    dependencies: [.package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20")],
    targets: [
        .executableTarget(name: "Lexikos", dependencies: ["ZIPFoundation"], exclude: ["iOS"]),
        .testTarget(name: "LexikosTests", dependencies: ["Lexikos"]),
    ]
)
