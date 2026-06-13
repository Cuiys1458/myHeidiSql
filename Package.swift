// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacHeidi",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "MacHeidiCore",  targets: ["MacHeidiCore"]),
        .library(name: "MacHeidiMySQL", targets: ["MacHeidiMySQL"]),
        .executable(name: "MacHeidiApp", targets: ["MacHeidiApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/mysql-nio.git", from: "1.7.0"),
    ],
    targets: [
        .target(name: "MacHeidiCore", path: "Sources/MacHeidiCore"),
        .target(
            name: "MacHeidiMySQL",
            dependencies: [
                "MacHeidiCore",
                .product(name: "MySQLNIO", package: "mysql-nio"),
            ],
            path: "Sources/MacHeidiMySQL"
        ),
        .executableTarget(
            name: "MacHeidiApp",
            dependencies: ["MacHeidiCore", "MacHeidiMySQL"],
            path: "Sources/MacHeidiApp",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "MacHeidiCoreTests",
            dependencies: ["MacHeidiCore"],
            path: "Tests/MacHeidiCoreTests"
        ),
        .testTarget(
            name: "MacHeidiMySQLTests",
            dependencies: ["MacHeidiMySQL"],
            path: "Tests/MacHeidiMySQLTests"
        ),
    ]
)
