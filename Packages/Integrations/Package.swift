// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Integrations",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "Integrations", targets: ["Integrations"]),
    ],
    dependencies: [
        .package(path: "../TimesheetCore"),
    ],
    targets: [
        .target(
            name: "Integrations",
            dependencies: [
                .product(name: "TimesheetCore", package: "TimesheetCore"),
            ]),
        .testTarget(name: "IntegrationsTests", dependencies: ["Integrations"]),
    ]
)
