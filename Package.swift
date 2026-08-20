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
        .executable(name: "GoldenEyeOriginalFrontendSmoke", targets: ["GoldenEyeOriginalFrontendSmoke"]),
    ],
    targets: [
        .target(
            name: "GoldenEyeNative",
            path: "native",
            exclude: ["host", "shaders", "tests", "include/ge_original_frontend_v6.h"],
            sources: [
                "src/goldeneye_native.c",
                "src/ge_classic_replay.c",
                "src/ge_texture_decode.c",
                "src/ge_texture_replay.c",
                "src/ge_classic_combiner.c",
                "src/ge_classic_raster_v5.c",
                "src/ge_title_raster_v5.c",
                "src/ge_native_runtime_v5.c",
                "src/ge_audio_v5.c",
                "src/ge_audio_effects_v6.c",
                "src/ge_ramrom_v5.c",
                "src/ge_audio_engine_v5.c",
                "src/ge_audio_output_v5.c",
                "src/ge_audio_source_node_v5.m",
                "source_port/gameplay_v6/ge_ramrom_gameplay_v6.c",
                "source_port/gameplay_v6/ge_guard_door_owner_v6.c",
                "source_port/gameplay_v6/ge_player_camera_owner_v6.c",
                "source_port/gameplay_v6/ge_weapon_effect_owner_v6.c",
                "source_port/gameplay_v6/ge_ramrom_weapon_source_pages_v6.c",
                "src/ge_stage_v5.c",
                "src/ge_stage_background_v5.c",
                "src/ge_ramrom_playback_v5.c",
                "src/ge_title_route_v5.c",
                "src/ge_source_scene_v6.c",
                "src/ge_source_reference_v6.c",
                "src/ge_source_gbi_v6.c",
                "src/ge_source_texture_coordinates_v6.c",
                "src/ge_source_frontend_runtime_v6.c",
                "src/ge_file_mode_v6.c",
                "source_port/ge_source_frontend_v6.c"
            ],
            publicHeadersPath: "include"
        ),
        .target(
            name: "GoldenEyeOriginalFrontend",
            path: "native/source_port/original",
            exclude: [
                "ge_original_frontend_v6_smoke.c",
                "ge_original_frontend_v6_swift_bridge.h",
                "ge_original_frontend_v6_swift_smoke.swift",
                "ge_original_swiftpm_integration_v6.md"
            ],
            sources: [
                "ge_original_front_c.c",
                "ge_original_title_c.c",
                "ge_original_frontend_v6.c",
                "ge_original_host_stubs.c",
                "ge_original_production_weak_stubs.c"
            ],
            publicHeadersPath: "public",
            cSettings: [
                .define("_LANGUAGE_C"),
                .define("VERSION_US"),
                .define("LANG_US"),
                .define("REFRESH_NTSC"),
                .define("LEFTOVERDEBUG"),
                .define("LEFTOVERSPECTRUM"),
                .define("BUGFIX_R0"),
                .define("BYTEMATCH"),
                .define("GE_ORIGINAL_FRONTEND_PRODUCTION"),
                .headerSearchPath("../../../"),
                .headerSearchPath("../../../include"),
                .headerSearchPath("../../../src"),
                .headerSearchPath("../../../src/game"),
                .headerSearchPath("../../../src/inflate"),
                .headerSearchPath("../../include"),
                .unsafeFlags([
                    "-fno-modules",
                    "-fno-implicit-modules",
                    "-Wno-error=implicit-function-declaration",
                    "-Wno-implicit-function-declaration",
                    "-Wno-error=return-type",
                    "-Wno-return-type"
                ])
            ]
        ),
        .executableTarget(
            name: "GoldenEyeOriginalFrontendSmoke",
            dependencies: ["GoldenEyeOriginalFrontend", "GoldenEyeNative"],
            path: "native/source_port/original/swiftpm_smoke"
        ),
        .executableTarget(
            name: "GoldenEyeHost",
            dependencies: ["GoldenEyeNative", "GoldenEyeOriginalFrontend"],
            path: "native/host",
            exclude: ["NativeBootInfo.plist"]
        ),
    ]
)
