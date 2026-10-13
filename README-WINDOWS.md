# Aftermath analysis on Windows

This fork adds a Swift Package Manager build that runs **only Aftermath's analysis mode** (`--analyze`) on Windows (and Linux). Collection still happens on the Mac with the regular Aftermath build; you then copy the collection zip to Windows and analyze it there.

The macOS Xcode project is unchanged and still builds the full collector.

**Just want to run it?** Download `aftermath-windows-x64.zip` from the [Releases](https://github.com/purpl3horse/aftermath-windows/releases) page, extract it, and skip to [step 3](#3-analyze-a-collection). It needs Windows 10 (1803) or later x64 and the Microsoft Visual C++ Redistributable (x64), which most systems already have. Keep the DLLs next to `aftermath.exe`.

## 1. Install the Swift toolchain

Visual Studio 2022 does not compile Swift itself, but the Swift toolchain uses VS 2022's C++ build tools and Windows SDK. Open the **Visual Studio Installer → Modify** and make sure these are installed:

- MSVC v143 – VS 2022 C++ x64/x86 build tools
- Windows 11 SDK (10.0.22621 or later)

Then install Swift 6.0 or later. Either download the installer from swift.org/install/windows (for example `swift-6.4.0-RELEASE-windows10.exe`), or use winget:

```powershell
winget install --id Swift.Toolchain -e --source winget
```

You also need **Git** (git-scm.com), which the build uses to fetch the SQLite package.

## 2. Build

Open **x64 Native Tools Command Prompt for VS 2022** from the Start menu. A plain PowerShell window may fail with `'stdlib.h' file not found`, because it doesn't have the Windows SDK paths set. In that prompt:

```
cd <path>\aftermath-windows
swift build -c release
```

The first build fetches the SQLite package from GitHub and compiles it, so it takes a few minutes.

The program is written to:

```
.build\out\Products\Release-windows-x86_64\aftermath.exe
```

(`swift build -c release --show-bin-path` prints the folder.) A warning that `.build\release` couldn't be created as a symbolic link is harmless; it only appears when Windows Developer Mode is off.

### Packaging for other machines

`aftermath.exe` loads the Swift runtime DLLs (`swiftCore.dll`, `Foundation.dll`, `FoundationEssentials.dll` and the DLLs those load); `--static-swift-stdlib` does not remove them on Windows. To run it on a PC without Swift, ship those DLLs next to it:

```
mkdir C:\tmp\aftermath-windows-x64
copy .build\out\Products\Release-windows-x86_64\aftermath.exe C:\tmp\aftermath-windows-x64\
copy "%LOCALAPPDATA%\Programs\Swift\Runtimes\6.4.0\usr\bin\*.dll" C:\tmp\aftermath-windows-x64\
copy LICENSE.md C:\tmp\aftermath-windows-x64\
powershell -Command "Compress-Archive -Path C:\tmp\aftermath-windows-x64\* -DestinationPath C:\tmp\aftermath-windows-x64.zip -Force"
```

Adjust `6.4.0` to the folder under `%LOCALAPPDATA%\Programs\Swift\Runtimes`. Test the zip on a machine without Swift (`aftermath.exe --version`) before publishing it. The other dependencies (`KERNEL32.dll`, `VCRUNTIME140.dll`, `api-ms-win-crt-*.dll`) are part of Windows and the Visual C++ Redistributable.

## 3. Analyze a collection

```powershell
aftermath.exe --analyze C:\Cases\Aftermath_C02XYZ.zip -o C:\Cases
```

- `--analyze` takes the collection zip from the Mac, or a folder where you already extracted it.
- `-o` is a folder (or a full `...\name.zip` path) for the results. It defaults to the current folder.
- `--pretty` colors the console output.

No administrator rights are needed. Zip files are read and written with Windows' built-in `tar.exe` (Windows 10 version 1803 or later).

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
- `analyze/Portability.swift` – opens the collection zip and finds the collection folder by its contents, so a renamed zip still works. On Windows (and Linux) it uses the system's bsdtar (`tar.exe`), because ZIPFoundation needs a zlib library Windows doesn't have; entries that can't be written, such as names Windows can't store, are skipped instead of aborting the extraction. On macOS it uses ZIPFoundation and renames such entries.
- `aftermath/Module.swift`, `aftermath/CaseFiles.swift` – zipping and unzipping use ZIPFoundation when it is available and `tar` otherwise. Mac-only code (IOKit serial, Accelerate, Spotlight metadata, user enumeration from `/var/db/dslocal`, `/tmp` temp zip) is behind `#if !AFTERMATH_ANALYZE_ONLY`. Without the flag (the Xcode build) the code is exactly as before.
- `analysis/*.swift` – `import SQLite3` falls back to the bundled SQLite on Windows/Linux, and database paths are passed to SQLite in native form (`C:\...`).
- `aftermath/Aftermath.swift` – **bug fix that also affects macOS:** `sortCSV` never reordered rows (its guard was inverted) and would throw on timestamps already ending in `Z`. The storyline and timeline are now actually sorted, newest first.

## Known limitations (same as upstream)

- The analyzer splits CSV lines on commas, so values containing commas can shift columns.
- Browser storyline rows carry a stray `)` after the URL (upstream typo, left as is).
- Collection itself (everything except `--analyze`) only runs on macOS.
