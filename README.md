# aftermath-windows

A fork of Jamf's [Aftermath](https://github.com/jamf/aftermath), the macOS incident-response collection and analysis tool, that runs Aftermath's **analysis mode (`--analyze`) on Windows**.

Collection still happens on the Mac with the original Aftermath. Copy the resulting `Aftermath_<serial>.zip` to a Windows machine and analyze it there.

## Download

Get `aftermath-windows-x64.zip` from the [Releases](https://github.com/purpl3horse/aftermath-windows/releases) page. No build or Swift installation needed.

**Requirements**
- Windows 10 (version 1803) or later, 64-bit (x64)
- Microsoft Visual C++ Redistributable 2015–2022 (x64), already present on most systems; otherwise [download it from Microsoft](https://aka.ms/vs/17/release/vc_redist.x64.exe)
- No administrator rights needed

Extract the zip and keep the DLLs in the same folder as `aftermath.exe`; they are the Swift runtime it needs.

## Usage

```
aftermath.exe --analyze C:\Cases\Aftermath_C02XYZ.zip -o C:\Cases
```

- `--analyze` takes the collection zip from the Mac, or an already-extracted collection folder.
- `-o` is the output folder (or a full `...\name.zip` path). It defaults to the current folder.
- `--pretty` colors the console output, `--version` prints the version.

The output is `Aftermath_Analysis_<serial>.zip` with `storyline.csv`, `file_timeline.csv`, `tcc.csv`, `lsquarantine.csv`, `xpdb.csv`, `provenance.csv` and `logs.csv`, ready for Excel or Timeline Explorer.

## Build from source

Requirements: Visual Studio 2022 with the C++ build tools and Windows 11 SDK, Swift 6.0 or later, and Git.

In the **x64 Native Tools Command Prompt for VS 2022**:

```
swift build -c release
```

The program is written to `.build\out\Products\Release-windows-x86_64\aftermath.exe` (`swift build -c release --show-bin-path` prints the folder).

Full build and usage notes, including troubleshooting, are in [README-WINDOWS.md](README-WINDOWS.md).

## How it differs from the macOS version

**What's included**
- Only `--analyze`, plus `-o` and `--pretty`. Collection options (`--deep`, `--es-logs`, `--disable`, …) are rejected with a message, because collection reads macOS-only system data.
- The analysis engine (`analysis/`) is Jamf's code, unchanged apart from portable imports and paths.

**Build**
- A new `Package.swift` (Swift Package Manager) builds the Windows version. The original `aftermath.xcodeproj` still builds the full macOS tool and is unaffected.
- Mac-only code (IOKit, Accelerate, Spotlight metadata, local user lookup) is compiled out behind an `AFTERMATH_ANALYZE_ONLY` flag that only this package sets.
- SQLite comes from the bundled `swift-toolchain-sqlite` package instead of the macOS SDK.
- Zip files are handled by Windows' built-in `tar.exe` instead of ZIPFoundation, which needs a zlib library Windows doesn't have.

**Behaviour**
- No root/administrator check, and results go to the current folder by default instead of `/tmp`.
- Extraction keeps going past files Windows can't store (names with `:`, `?`, `*` and so on), skips symlinks and `__MACOSX`, and finds the collection folder by its contents, so a renamed zip still works.
- You can pass an already-extracted collection folder instead of the zip.
- Temporary files are cleaned up after the run.
- Output is written in batches instead of reopening the file for every line, so large collections take seconds instead of tens of minutes on Windows.

**Bug fix that also applies to macOS**
- Upstream's `sortCSV` never reordered rows, so the storyline and file timeline weren't sorted. They're now sorted newest first.

## Files added or changed

| File | Change |
|---|---|
| `Package.swift` | New: Windows/Linux build of the analyzer |
| `analyze/AnalyzeCommand.swift` | New: analyze-only command line |
| `analyze/Portability.swift` | New: zip handling and Windows-safe extraction |
| `aftermath/Aftermath.swift` | Sorting fix |
| `aftermath/CaseFiles.swift`, `aftermath/Module.swift` | Mac-only code behind the build flag; zip via `tar` when ZIPFoundation isn't available |
| `analysis/DatabaseParser.swift` | Portable SQLite import, native paths for SQLite |
| `README-macOS.md` | The original Aftermath README |
| `README-WINDOWS.md` | Detailed Windows build and usage guide |

## Credit and license

Aftermath is © 2022 JAMF Software, LLC, released under the MIT License (see [LICENSE.md](LICENSE.md)). This fork keeps that license. For the original tool and its collection features, see [README-macOS.md](README-macOS.md) and [jamf/aftermath](https://github.com/jamf/aftermath).
