# Aftermath analysis on Windows

This fork adds a Swift Package Manager build that runs **only Aftermath's analysis mode** (`--analyze`) on Windows (and Linux). Collection still happens on the Mac with the regular Aftermath build; you then copy the collection zip to Windows and analyze it there.

The macOS Xcode project is unchanged and still builds the full collector.

## 1. Install the Swift toolchain

Visual Studio 2022 does not compile Swift itself, but the Swift toolchain uses VS 2022's C++ build tools and Windows SDK. Open the **Visual Studio Installer → Modify** and make sure these are installed:

- MSVC v143 – VS 2022 C++ x64/x86 build tools
- Windows 11 SDK (10.0.22621 or later)

Or install them from a terminal:

```powershell
winget install --id Microsoft.VisualStudio.2022.Community --exact --force --custom "--add Microsoft.VisualStudio.Component.Windows11SDK.22621 --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64" --source winget
```

Then install Swift:

```powershell
winget install --id Swift.Toolchain -e --source winget
```

Open a **new** terminal afterwards and check it works:

```powershell
swift --version
```

Swift 6.0 or later is required.

## 2. Build

From the repository folder:

```powershell
swift build -c release
```

The first build downloads two dependencies from GitHub (ZIPFoundation and the SQLite package) and compiles SQLite, so it takes a few minutes. The program ends up at:

```
.build\release\aftermath.exe
```

You can copy `aftermath.exe` anywhere. If Windows complains about missing Swift DLLs when it's run on a machine without the Swift toolchain, copy the Swift runtime DLLs next to it (with a winget install they are typically in `%LOCALAPPDATA%\Programs\Swift\Runtimes\<version>\usr\bin`).

## 3. Analyze a collection

```powershell
aftermath.exe --analyze C:\Cases\Aftermath_C02XYZ.zip -o C:\Cases
```

- `--analyze` takes the collection zip from the Mac, or a folder where you already extracted it.
- `-o` is a folder (or a full `...\name.zip` path) for the results. It defaults to the current folder.
- `--pretty` colors the console output.

No administrator rights are needed.

The result is `Aftermath_Analysis_<name>.zip`, the same as on macOS, containing:

| File | Contents |
|---|---|
| `storyline.csv` | Everything below merged into one timeline, newest first |
| `file_timeline.csv` | Birth/modified/accessed times of collected files |
| `tcc.csv` | Privacy (TCC) permission grants |
| `lsquarantine.csv` | Quarantine (download) events |
| `xpdb.csv` | XProtect Behavior Service detections |
| `provenance.csv` | Provenance tracking records |
| `logs.csv` | install.log, system.log and XProtect Remediator entries |
| `system_information.txt` | System details from the collection |
| `aftermath_analysis.log` | Log of the analysis run |

These open in Excel, or in Eric Zimmerman's Timeline Explorer for large files.

## What changed compared to upstream

- `Package.swift` – SwiftPM target that compiles the analysis engine plus the shared helpers, with the `AFTERMATH_ANALYZE_ONLY` flag set. The macOS collector sources are excluded.
- `analyze/AnalyzeCommand.swift` – analyze-only entry point (replaces `aftermath/Command.swift` in this build only). No root check, Windows-friendly default output folder, clear errors for collection-only options.
- `analyze/Portability.swift` – extracts the collection entry by entry. File names Windows can't store (`:`, `?`, `*`, trailing dots, `CON`, …) are renamed instead of aborting the extraction; symlinks and `__MACOSX` entries are skipped; the collection folder is found by its contents, so a renamed zip still works.
- `aftermath/Module.swift`, `aftermath/CaseFiles.swift` – Mac-only code (IOKit serial, Accelerate, Spotlight metadata, user enumeration from `/var/db/dslocal`, `/tmp` temp zip) is behind `#if !AFTERMATH_ANALYZE_ONLY`. Without the flag (the Xcode build) the code is exactly as before.
- `analysis/*.swift` – `import SQLite3` falls back to the bundled SQLite on Windows/Linux, and database paths are passed to SQLite in native form (`C:\...`).
- `aftermath/Aftermath.swift` – **bug fix that also affects macOS:** `sortCSV` never reordered rows (its guard was inverted) and would throw on timestamps already ending in `Z`. The storyline and timeline are now actually sorted, newest first.

## Known limitations (same as upstream)

- The analyzer splits CSV lines on commas, so values containing commas can shift columns.
- Browser storyline rows carry a stray `)` after the URL (upstream typo, left as is).
- Collection itself (everything except `--analyze`) only runs on macOS.
