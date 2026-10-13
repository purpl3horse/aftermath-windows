//
//  Portability.swift
//  aftermath (analyze-only build)
//
//  Opening a macOS collection on another OS. The macOS build unzips with
//  FileManager.unzipItem, which stops at the first entry that fails and assumes
//  the folder inside the zip is named like the zip. On Windows, files collected
//  from a Mac can have names Windows rejects (":" "?" "*" trailing dots, CON, ...),
//  so this extracts entry by entry, renames what Windows can't store, and finds
//  the collection folder by its contents.
//

import Foundation
import ZIPFoundation

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

        let archive: Archive
        do {
            archive = try Archive(url: URL(fileURLWithPath: input), accessMode: .read)
        } catch {
            module.log("Unable to open \(input) as a zip archive: \(error)")
            try? fm.removeItem(at: extractRoot)
            return nil
        }

        module.log("Extracting \(input)...")
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

        guard let root = locateCollectionRoot(in: extractRoot) else {
            try? fm.removeItem(at: extractRoot)
            return nil
        }
        return PreparedCollection(collectionDir: root.path, temporaryExtractionDir: extractRoot)
    }

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
