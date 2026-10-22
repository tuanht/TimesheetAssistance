// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TimesheetCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TimesheetCore", targets: ["TimesheetCore"]),
    ],
    targets: [
        .target(name: "TimesheetCore"),
        .testTarget(name: "TimesheetCoreTests", dependencies: ["TimesheetCore"]),
    ]
)
