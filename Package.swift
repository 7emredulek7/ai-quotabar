// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "AIQuotabar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "AIQuotabar",
            path: "Sources/AIQuotabar",
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
