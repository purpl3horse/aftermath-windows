//
//  Portability.swift
//  aftermath (analyze-only build)
//
//  Opening a macOS collection on another OS.
//
//  The upstream macOS build unzips with FileManager.unzipItem, which stops at the
//  first entry that fails and assumes the folder inside the zip is named like the
//  zip. Files collected from a Mac can have names Windows rejects (":" "?" "*",
//  trailing dots, CON, ...), so this keeps going past failed entries and finds the
//  collection folder by its contents.
//
//  On macOS, ZIPFoundation is used and invalid names are renamed entry by entry.
//  On Windows and Linux, the OS's bsdtar does the zip work (ZIPFoundation needs a
//  system zlib that Windows doesn't have). Windows' tar.exe replaces characters that
//  are invalid in Windows file names with "_" and continues past entries it can't
//  write, which only affects files the analysis doesn't read.
//

import Foundation
#if canImport(ZIPFoundation)
import ZIPFoundation
#endif

struct PreparedCollection {
    /// Folder to hand to AnalysisModule (the one holding metadata.csv, Artifacts, ...)
    let collectionDir: String
    /// Temporary extraction folder to delete afterwards; nil when the input was a folder
    let temporaryExtractionDir: URL?
}

enum CollectionArchive {

    /// Folders and files an Aftermath collection has at its top level.
    static let markers = ["metadata.csv", "Artifacts", "Recon", "Browser", "Processes", "UnifiedLog"]

    static func prepare(input: String, module: AftermathModule) -> PreparedCollection? {
        let fm = FileManager.default

        if fm.isDirectoryThatExists(path: input) {
            guard let root = locateCollectionRoot(in: URL(fileURLWithPath: input)) else { return nil }
            return PreparedCollection(collectionDir: root.path, temporaryExtractionDir: nil)
        }

        let extractRoot = fm.temporaryDirectory.appendingPathComponent("Aftermath_Extract_\(UUID().uuidString.prefix(8))")
        do {
            try fm.createDirectory(at: extractRoot, withIntermediateDirectories: true)
        } catch {
            module.log("Unable to create extraction folder \(extractRoot.nativePath): \(error)")
            return nil
        }

        module.log("Extracting \(input)...")
        #if canImport(ZIPFoundation)
        guard extractWithZIPFoundation(input: input, to: extractRoot, module: module) else {
            try? fm.removeItem(at: extractRoot)
            return nil
        }
        #else
        do {
            try SystemArchiver.extract(archive: URL(fileURLWithPath: input), to: extractRoot)
        } catch SystemArchiver.Failure.partial(let details) {
            // Some entries couldn't be written; the analysis usually doesn't need them
            module.log("Some entries could not be extracted (usually files whose names Windows can't store):\n\(details)", displayOnly: true)
        } catch {
            module.log("Unable to extract \(input): \(error)")
            try? fm.removeItem(at: extractRoot)
            return nil
        }
        #endif

        guard let root = locateCollectionRoot(in: extractRoot) else {
            try? fm.removeItem(at: extractRoot)
            return nil
        }
        return PreparedCollection(collectionDir: root.path, temporaryExtractionDir: extractRoot)
    }

    #if canImport(ZIPFoundation)
    /// Extracts entry by entry, renaming names Windows can't store and skipping
    /// symlinks, Finder metadata and paths that would escape the extraction folder.
    private static func extractWithZIPFoundation(input: String, to extractRoot: URL, module: AftermathModule) -> Bool {
        let fm = FileManager.default
        let archive: Archive
        do {
            archive = try Archive(url: URL(fileURLWithPath: input), accessMode: .read)
        } catch {
            module.log("Unable to open \(input) as a zip archive: \(error)")
            return false
        }

        var extracted = 0, renamed = 0, skipped = 0

        for entry in archive {
            if entry.type == .symlink {
                skipped += 1 // not needed for analysis, and need admin rights on Windows
                continue
            }

            let original = entry.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            // Ignore Finder metadata and anything trying to escape the extraction folder
            if original.first == "__MACOSX" || original.contains("..") || original.isEmpty {
                skipped += 1
                continue
            }

            let safe = original.map(sanitizeComponent)
            if safe != original { renamed += 1 }

            let destination = safe.reduce(extractRoot) { $0.appendingPathComponent($1) }
            do {
                if entry.type == .directory {
                    try fm.createDirectory(at: destination, withIntermediateDirectories: true)
                } else {
                    try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
                    _ = try archive.extract(entry, to: destination, skipCRC32: true)
                }
                extracted += 1
            } catch {
                skipped += 1
                module.log("Could not extract \(entry.path): \(error)", displayOnly: true)
            }
        }

        module.log("Extracted \(extracted) entries (\(renamed) renamed for this OS, \(skipped) skipped)")

        return true
    }
    #endif

    /// Finds the collection folder: the given folder itself, or a folder up to two
    /// levels below it, that contains Aftermath's top-level files.
    static func locateCollectionRoot(in dir: URL) -> URL? {
        let fm = FileManager.default

        func isCollection(_ url: URL) -> Bool {
            let found = markers.filter { fm.fileExists(atPath: url.appendingPathComponent($0).path) }
            return found.count >= 2
        }

        func subdirectories(of url: URL) -> [URL] {
            let items = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
            return items.filter { fm.isDirectoryThatExists(path: $0.path) }
                        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        }

        if isCollection(dir) { return dir }
        for child in subdirectories(of: dir) {
            if isCollection(child) { return child }
            for grandchild in subdirectories(of: child) where isCollection(grandchild) {
                return grandchild
            }
        }
        return nil
    }

    /// Makes a single path component valid on Windows (and leaves valid names alone):
    /// replaces <>:"/\|?* and control characters, trims trailing dots and spaces,
    /// and prefixes reserved device names such as CON or NUL.
    static func sanitizeComponent(_ name: String) -> String {
        let invalid: Set<Character> = ["<", ">", ":", "\"", "/", "\\", "|", "?", "*"]
        var result = String(name.map { ch -> Character in
            if invalid.contains(ch) { return "_" }
            if let ascii = ch.asciiValue, ascii < 0x20 { return "_" }
            return ch
        })

        while let last = result.last, last == "." || last == " " {
            result.removeLast()
        }
        if result.isEmpty && !name.isEmpty { result = "_" }

        let reserved: Set<String> = ["CON", "PRN", "AUX", "NUL",
                                     "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
                                     "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"]
        let stem = result.split(separator: ".", maxSplits: 1).first.map { String($0).uppercased() } ?? ""
        if reserved.contains(stem) { result = "_" + result }

        return result
    }
}

/// Zip extraction and creation with the operating system's bsdtar
/// (C:\Windows\System32\tar.exe on Windows 10 1803 and later).
enum SystemArchiver {
    enum Failure: Error, CustomStringConvertible {
        case tarNotFound
        case failed(String)
        case partial(String)

        var description: String {
            switch self {
            case .tarNotFound:
                return "tar.exe was not found. It is built into Windows 10 (1803) and later in C:\\Windows\\System32; on Linux install bsdtar (libarchive-tools)."
            case .failed(let output): return "tar failed: \(output)"
            case .partial(let output): return output
            }
        }
    }

    /// Unpacks a zip into `destination`. Throws `.partial` when tar extracted the archive
    /// but reported problems with some entries.
    static func extract(archive: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let before = (try? FileManager.default.contentsOfDirectory(atPath: destination.path)) ?? []
        let (status, output) = try run(["-x", "-f", archive.nativePath, "-C", destination.nativePath])
        if status == 0 { return }
        let after = (try? FileManager.default.contentsOfDirectory(atPath: destination.path)) ?? []
        throw after.count > before.count ? Failure.partial(output) : Failure.failed(output)
    }

    /// Zips `directory` (keeping the folder itself as the top level) into `zipURL`.
    static func zip(directory: URL, to zipURL: URL) throws {
        let parent = directory.deletingLastPathComponent()
        let (status, output) = try run(["--format", "zip", "-c", "-f", zipURL.nativePath,
                                        "-C", parent.nativePath, directory.lastPathComponent])
        if status != 0 { throw Failure.failed(output) }
    }

    private static func tarExecutable() -> URL? {
        let fm = FileManager.default
        var candidates: [String] = []
        #if os(Windows)
        let systemRoot = ProcessInfo.processInfo.environment["SystemRoot"] ?? "C:\\Windows"
        candidates.append("\(systemRoot)\\System32\\tar.exe")
        #else
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        for dir in path.split(separator: ":") {
            candidates.append("\(dir)/bsdtar")   // GNU tar can't read or write zip files
        }
        #endif
        return candidates.first { fm.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    private static func run(_ arguments: [String]) throws -> (Int32, String) {
        guard let tar = tarExecutable() else { throw Failure.tarNotFound }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = tar
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
