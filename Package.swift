// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GoldenEyeSwift",
    // The goal targets macOS 27. Keep the package deployment target aligned
    // with the bundle's LSMinimumSystemVersion so the executable cannot
    // silently advertise an older Mach-O minimum.
    platforms: [.macOS("27.0")],
    products: [
        .executable(name: "GoldenEyeHost", targets: ["GoldenEyeHost"]),
    ],
    targets: [
        .target(
            name: "GoldenEyeNative",
            path: "native",
            exclude: ["host", "shaders", "tests"],
            sources: ["src/goldeneye_native.c", "src/ge_classic_replay.c", "src/ge_texture_decode.c", "src/ge_texture_replay.c"],
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "GoldenEyeHost",
            dependencies: ["GoldenEyeNative"],
            path: "native/host"
        ),
    ]
)
