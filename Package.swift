// swift-tools-version:6.0
//
// Package.swift
//
// SwiftPM build of Aftermath's analysis mode (`aftermath --analyze`) only.
// It runs on Windows (and Linux) as well as macOS, and analyzes a collection
// zip that was produced by the regular macOS build of Aftermath.
//
// The full collector is still built with aftermath.xcodeproj on macOS; this
// package does not change that build.

import PackageDescription

let package = Package(
    name: "aftermath",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "aftermath", targets: ["aftermath"])
    ],
    dependencies: [
        // Windows support in ZIPFoundation is on its main branch but not yet in a
        // tagged release (0.9.20 and earlier lack it), so this pins a known revision.
        .package(url: "https://github.com/weichsel/ZIPFoundation.git",
                 revision: "e7a17d57c583067eaa6659cd6d9521265b7664e9"),
        // SQLite for platforms whose SDK has no SQLite3 module (Windows, Linux).
        // This is the same amalgamation package SwiftPM itself uses on Windows.
        .package(url: "https://github.com/swiftlang/swift-toolchain-sqlite.git",
                 from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "aftermath",
            dependencies: [
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
                .product(name: "SwiftToolchainCSQLite", package: "swift-toolchain-sqlite",
                         condition: .when(platforms: [.windows, .linux])),
            ],
            path: ".",
            exclude: [
                // macOS collector code and project files, built only by aftermath.xcodeproj
                "aftermath/main.swift", "aftermath/Command.swift",
                "artifacts", "endpointSecurity", "filesystem", "helpers", "libs", "network",
                "persistence", "processes", "systemRecon", "unifiedlogs", "tests",
                "extensions/Collection.swift", "extensions/Data.swift",
                "extensions/String.swift", "extensions/URL.swift",
                "aftermath.xcodeproj", "AftermathLogo.png", "CODEOWNERS",
                "LICENSE.md", "README.md", "README-WINDOWS.md",
            ],
            sources: [
                // Shared Aftermath code (Mac-only parts are compiled out by the flag below)
                "aftermath/Aftermath.swift",
                "aftermath/CaseFiles.swift",
                "aftermath/Module.swift",
                "extensions/FileManager.swift",
                // The analysis engine, unchanged apart from portable imports and paths
                "analysis/AnalysisModule.swift",
                "analysis/DatabaseParser.swift",
                "analysis/LogParser.swift",
                "analysis/ProcessParser.swift",
                "analysis/Storyline.swift",
                "analysis/Timeline.swift",
                // Analyze-only entry point and portability helpers
                "analyze/AnalyzeCommand.swift",
                "analyze/Portability.swift",
            ],
            swiftSettings: [
                .define("AFTERMATH_ANALYZE_ONLY"),
                .swiftLanguageMode(.v5),
            ]
        )
    ]
)
