// swift-tools-version:5.10
// HCG System Tester — Hakmi Capital Group
//
// Layout:
//   HCGCore            Platform-neutral engine (models, identification, adapter SDK,
//                      diagnostics, laboratory, reports, redaction). Builds on macOS and Linux.
//   HCGHardware        Real hardware discovery backends (IOKit on macOS).
//   HCGSystemTesterUI  SwiftUI workstation interface (macOS only).
//   HCGSystemTester    SwiftPM executable that launches the app (`swift run HCGSystemTester`).
//   hcg-probe          Command-line discovery probe (`swift run hcg-probe --watch`).
//
// The Xcode project in App/ links the same library products to produce the signed .app bundle.
import PackageDescription

let package = Package(
    name: "HCGSystemTester",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "HCGCore", targets: ["HCGCore"]),
        .library(name: "HCGHardware", targets: ["HCGHardware"]),
        .library(name: "HCGSystemTesterUI", targets: ["HCGSystemTesterUI"]),
        .executable(name: "HCGSystemTester", targets: ["HCGSystemTester"]),
        .executable(name: "hcg-probe", targets: ["hcg-probe"])
    ],
    targets: [
        .target(
            name: "HCGCore",
            path: "Sources/HCGCore"
        ),
        .target(
            name: "HCGHardware",
            dependencies: ["HCGCore"],
            path: "Sources/HCGHardware",
            linkerSettings: [
                .linkedFramework("IOKit", .when(platforms: [.macOS])),
                .linkedFramework("CoreFoundation", .when(platforms: [.macOS]))
            ]
        ),
        .target(
            name: "HCGSystemTesterUI",
            dependencies: ["HCGCore", "HCGHardware"],
            path: "Sources/HCGSystemTesterUI"
        ),
        .executableTarget(
            name: "HCGSystemTester",
            dependencies: ["HCGSystemTesterUI"],
            path: "Sources/HCGSystemTester"
        ),
        .executableTarget(
            name: "hcg-probe",
            dependencies: ["HCGCore", "HCGHardware"],
            path: "Sources/hcg-probe"
        ),
        .testTarget(
            name: "HCGCoreTests",
            dependencies: ["HCGCore"],
            path: "Tests/HCGCoreTests"
        ),
        .testTarget(
            name: "HCGHardwareTests",
            dependencies: ["HCGHardware", "HCGCore"],
            path: "Tests/HCGHardwareTests"
        )
    ]
)
