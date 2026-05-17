// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QueryTest",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "QueryTest",
            path: "Sources/QueryTest"
        )
    ]
)
