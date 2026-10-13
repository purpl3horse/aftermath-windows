//
//  AnalyzeCommand.swift
//  aftermath (analyze-only build)
//
//  Entry point for the SwiftPM build in Package.swift, which runs Aftermath's
//  analysis mode on Windows, Linux or macOS. It replaces aftermath/Command.swift
//  (the macOS collector's entry point) in that build only, and keeps the same
//  `Command` / `Options` names so the shared modules compile unchanged.
//
//  Usage:  aftermath --analyze <collection.zip | extracted folder> [-o <dir | file.zip>] [--pretty]
//

import Foundation

struct Options: OptionSet {
    let rawValue: Int

    static let deep = Options(rawValue: 1 << 0)
    static let output = Options(rawValue: 1 << 1)
    static let analyze = Options(rawValue: 1 << 2)
    static let pretty = Options(rawValue: 1 << 3)
    static let collectDirs = Options(rawValue: 1 << 4)
    static let unifiedLogs = Options(rawValue: 1 << 5)
    static let esLogs = Options(rawValue: 1 << 6)
    static let disable = Options(rawValue: 1 << 7)
}

@main
class Command {
    // This build only analyzes, so .analyze is always set (AftermathModule reads it
    // to choose the analysis log and case directory).
    static var options: Options = [.analyze]
    static var analysisDir: String? = nil
    // The macOS build defaults to /tmp; here the default is the current directory.
    static var outputLocation: String = FileManager.default.currentDirectoryPath
    static let version: String = "2.3.0 (analyze-only)"
    static var disableFeatures: [String: Bool] = ["all": false, "browsers": false, "browser-killswitch": false, "databases": false, "filesystem": false, "proc-info": false, "slack": false, "ul": false]

    static func main() {
        setup(with: CommandLine.arguments)
        start()
    }

    static func setup(with fullArgs: [String]) {
        let args = [String](fullArgs.dropFirst())

        if args.isEmpty {
            printHelp()
        }

        var index = 0
        while index < args.count {
            let arg = args[index]
            switch arg {
            case "-h", "--help":
                printHelp()
            case "-v", "--version":
                print(version)
                exit(0)
            case "--pretty":
                options.insert(.pretty)
            case "--analyze":
                analysisDir = value(after: index, in: args, for: arg)
                index += 1
            case "-o", "--output":
                options.insert(.output)
                outputLocation = value(after: index, in: args, for: arg)
                index += 1
            case "-d", "--deep", "--collect-dirs", "--disable", "--es-logs", "-l", "--logs", "--cleanup":
                print("\(arg) is a collection option and only works in the macOS build of Aftermath.")
                print("This build runs analysis only: aftermath --analyze <collection.zip>")
                exit(9)
            default:
                print("Unidentified argument: \(arg)")
                print("Run with --help for usage.")
                exit(9)
            }
            index += 1
        }

        if analysisDir == nil {
            print("This build of Aftermath runs analysis only. Pass --analyze <collection.zip>.")
            exit(9)
        }
    }

    private static func value(after index: Int, in args: [String], for flag: String) -> String {
        guard index + 1 < args.count, !args[index + 1].hasPrefix("-") else {
            print("\(flag) needs a value. Run with --help for usage.")
            exit(9)
        }
        return args[index + 1]
    }

    static func start() {
        printBanner()

        guard let input = analysisDir else { return }
        let fm = FileManager.default

        guard fm.fileExists(atPath: input) else {
            print("Analysis input not found: \(input)")
            exit(1)
        }

        // Same naming as the macOS build: Aftermath_<serial>.zip -> Aftermath_Analysis_<serial>
        let name = analysisName(from: input)
        let tempAnalysisDir = fm.temporaryDirectory.appendingPathComponent("Aftermath_Analysis_\(name)")
        try? fm.removeItem(at: tempAnalysisDir) // drop leftovers from an earlier run
        CaseFiles.CreateAnalysisCaseDir(filename: name)

        let mainModule = AftermathModule()
        mainModule.log("Running Aftermath Version \(version)")
        mainModule.log("Aftermath Analysis Started")
        mainModule.log("Analysis started at \(mainModule.getCurrentTimeStandardized().replacingOccurrences(of: ":", with: "_"))")

        guard let prepared = CollectionArchive.prepare(input: input, module: mainModule) else {
            mainModule.log("Could not find an Aftermath collection in \(input)")
            print("Could not find an Aftermath collection in \(input). Expected a zip (or folder) produced by Aftermath on macOS.")
            try? fm.removeItem(at: CaseFiles.analysisCaseDir)
            exit(1)
        }

        mainModule.log("Started analysis on Aftermath directory: \(prepared.collectionDir)")
        if #available(macOS 12, *) {
            let analysisModule = AnalysisModule(collectionDir: prepared.collectionDir)
            analysisModule.run()
            mainModule.log("Finished analysis module")
        }

        // Zip the analysis folder into the output location (same as the macOS build)
        CaseFiles.MoveTemporaryCaseDir(outputLocation: outputLocation, isAnalysis: true)
        mainModule.log("Aftermath Finished")

        // Remove the temporary copies. Unlike macOS, nothing cleans the temp folder later.
        if let extracted = prepared.temporaryExtractionDir {
            try? fm.removeItem(at: extracted)
        }
        if let zip = expectedOutputZip(), fm.fileExists(atPath: zip) {
            try? fm.removeItem(at: CaseFiles.analysisCaseDir)
        } else {
            // Zipping failed (e.g. a bad -o path): keep the results where they are.
            print("The analysis results are still available at \(CaseFiles.analysisCaseDir.nativePath)")
        }
    }

    /// The zip path CaseFiles.MoveTemporaryCaseDir writes for the current output location.
    static func expectedOutputZip() -> String? {
        let fm = FileManager.default
        if fm.isDirectoryThatExists(path: outputLocation) {
            return URL(fileURLWithPath: outputLocation)
                .appendingPathComponent(CaseFiles.analysisCaseDir.lastPathComponent)
                .appendingPathExtension("zip").path
        }
        if URL(fileURLWithPath: outputLocation).pathExtension == "zip" {
            return URL(fileURLWithPath: outputLocation).path
        }
        return nil
    }

    /// Derives the case name the macOS build uses: the text after the last "_" in
    /// the file name, without its extension (Aftermath_C02XYZ.zip -> C02XYZ).
    static func analysisName(from input: String) -> String {
        let base = URL(fileURLWithPath: input).deletingPathExtension().lastPathComponent
        let name = base.split(separator: "_").last.map(String.init) ?? base
        let safe = CollectionArchive.sanitizeComponent(name)
        return safe.isEmpty ? "collection" : safe
    }

    static func printHelp() {
        print("Aftermath \(version)")
        print("Analyzes a collection made by Aftermath on macOS. Collection itself only runs on macOS.")
        print("")
        print("--analyze -> analyze an Aftermath collection")
        print("     usage: --analyze <path_to_collection.zip>")
        print("            --analyze <path_to_extracted_collection_folder>")
        print("-o or --output -> where to write the analysis zip (defaults to the current directory)")
        print("     usage: -o C:\\Cases")
        print("            -o C:\\Cases\\analysis.zip")
        print("--pretty -> colorize terminal output")
        print("-v or --version -> print the version")
        exit(0)
    }

    static func printBanner() {
        print(#"""
              ___    ______                            __  __
             /   |  / __/ /____  _________ ___  ____ _/ /_/ /_
            / /| | / /_/ __/ _ \/ ___/ __ `__ \/ __ `/ __/ __ \
           / ___ |/ __/ /_/  __/ /  / / / / / / /_/ / /_/ / / /
          /_/  |_/_/  \__/\___/_/  /_/ /_/ /_/\__,_/\__/_/ /_/

        """#)
    }
}
