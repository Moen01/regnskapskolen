// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Regnskapsskolen",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Regnskapsskolen", targets: ["Regnskapsskolen"]),
    ],
    targets: [
        // Content, checkers, scheduler, sandbox and the claude runner. No UI, so it is testable.
        .target(name: "RegnskapKit"),
        .executableTarget(
            name: "Regnskapsskolen",
            dependencies: ["RegnskapKit"]
        ),
        .testTarget(
            name: "RegnskapKitTests",
            dependencies: ["RegnskapKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
