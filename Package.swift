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

// Zip handling. On macOS this uses ZIPFoundation, like the Xcode build. Elsewhere
// ZIPFoundation needs a system zlib that Windows doesn't have, so it isn't fetched
// at all and the OS's bsdtar does the zip work instead
// (C:\Windows\System32\tar.exe, built into Windows 10 1803 and later).
#if os(macOS)
let zipPackages: [Package.Dependency] = [
    .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
]
let zipProducts: [Target.Dependency] = [
    .product(name: "ZIPFoundation", package: "ZIPFoundation"),
]
#else
let zipPackages: [Package.Dependency] = []
let zipProducts: [Target.Dependency] = []
#endif

let package = Package(
    name: "aftermath",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "aftermath", targets: ["aftermath"])
    ],
    dependencies: zipPackages + [
        // SQLite for platforms whose SDK has no SQLite3 module (Windows, Linux).
        // This is the same amalgamation package SwiftPM itself uses on Windows.
        .package(url: "https://github.com/swiftlang/swift-toolchain-sqlite.git",
                 from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "aftermath",
            dependencies: zipProducts + [
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
