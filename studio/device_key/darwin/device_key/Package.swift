// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "device_key",
    platforms: [
        // CryptoKit's SecureEnclave keys need iOS 13 / macOS 10.15; macOS 12 as the app.
        .iOS("13.0"),
        .macOS("12.0"),
    ],
    products: [
        .library(name: "device-key", targets: ["device_key"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "device_key",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                // UserDefaults holds the Secure Enclave's wrapped key blobs (reason CA92.1).
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
