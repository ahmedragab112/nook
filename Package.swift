// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Nook",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Nook",
            path: "Sources/Nook",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Combine"),
                .linkedFramework("Carbon"),
                .linkedFramework("IOKit"),
                .linkedFramework("EventKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("ScreenCaptureKit", .when(platforms: [.macOS])),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedLibrary("compression")
            ]
        )
    ]
)
