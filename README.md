# TinyWin 11 Custom ISO Builder

A DISM-based Windows 11 ISO builder and unattended provisioning toolkit that creates a lightweight, debloated Windows 11 installation ISO with:

- **Custom OS Name & OEM Branding** (updates both WIM image selection metadata and Windows OEM registry info)
- **Regional, TimeZone & Keyboard Pre-Configuration** (keeps the Windows Setup language prompt while pre-configuring `GTB Standard Time` and English US + Greek keyboards `0409:00000409;0408:00000408`)
- **Hardware & Account Bypasses** (bypasses TPM 2.0, Secure Boot, RAM, CPU, Storage checks, and Microsoft Account requirement via `BypassNRO`)
- **Deep Debloat** (removes bloatware Appx packages, OneDrive, Edge browser while preserving WebView2 runtime, Copilot, Windows Recall, telemetry, and consumer ads)
- **Custom Desktop Wallpaper & UI Tweaks** (custom background image, Dark Mode, classic right-click context menu, visible file extensions)
- **Pre-Installed Applications**
  - **Winget + Direct Official Fallback**: Microsoft Visual C++ 2015–2022 Redistributable (x64 & x86), **LibreWolf**, and **TeamViewer**
  - **Offline Bundled Installers**: Drop your **MeshCentral** agent (`meshagent.exe`) or any `.exe`/`.msi` into `apps/installers/` to bundle and install automatically (`meshagent.exe -fullinstall` runs as `SYSTEM` during `SetupComplete`).

---

## Project Structure

- [config.json](config.json) — Central configuration for branding, regional settings, debloat list, wallpaper, drivers, and pre-installed apps.
- [Build-TinyWin11.ps1](Build-TinyWin11.ps1) — Main DISM & ISO builder script (run as Administrator).
- [Build-ISO.cmd](Build-ISO.cmd) — Double-click launcher; self-elevates and runs the builder with `-PreDownloadApps`.
- [scripts/Generate-Autounattend.ps1](scripts/Generate-Autounattend.ps1) — Generates [autounattend.xml](autounattend.xml) from `config.json`.
- [scripts/SetupComplete.ps1](scripts/SetupComplete.ps1) — Runs as `SYSTEM` at the end of Windows Setup to install system services (like `meshagent.exe -fullinstall`) and disable telemetry tasks/services.
- [scripts/FirstLogon.ps1](scripts/FirstLogon.ps1) — Runs at first user logon to apply desktop/UI tweaks and install VC++ Redistributables, LibreWolf, TeamViewer, and any bundled installers.
- [drivers/](drivers/README.md) — Offline `.inf` driver packages injected directly into the Windows DriverStore (`install.wim` and `boot.wim`). *Not tracked in git.*
  - `drivers/VirtIO/` — Windows 11 x64 VirtIO storage (`viostor`, `vioscsi`), network (`NetKVM`), input, and display INF drivers.
  - `drivers/Intel_POS_Common/` — Intel Chipset, UHD Graphics, CSME, and Serial IO x64 INF drivers.
  - `drivers/CQ-JY12-N150/` — Complete N150 POS terminal INF driver pack (Chipset, Graphics, GNA, ME, HID, SerialIO, DTT, Realtek Audio, MIPI Camera, Wi-Fi/BT Network, MXC6655).
- [iso/](iso/README.md) — Source Windows 11 ISO folder (auto-detected by `Build-TinyWin11.ps1`). *Not tracked in git.*
- [apps/installers/](apps/installers/README.md) — Folder for offline installers (e.g. `meshagent64-NewPCS.exe`). *Not tracked in git.*
- `apps/cache/` — Winget installer cache populated by `-PreDownloadApps`. *Not tracked in git.*
- [assets/wallpaper/](assets/wallpaper/README.md) — Folder for your custom desktop background (`wallpaper.jpg`).
- `tools/` — `oscdimg.exe` is auto-downloaded here if the Windows ADK is not installed. *Not tracked in git.*
- `output/` — Destination folder for the generated `POS_READY_2026.iso` and `build.log`. *Not tracked in git.*
- `work/` — Temporary DISM mount & ISO staging directory, recreated on every build. *Not tracked in git.*

---

## Requirements

- Windows 10/11 host with PowerShell 5.1+ and DISM (built in).
- Administrator privileges (required for DISM mount and offline registry editing).
- A Windows 11 x64 ISO (e.g. 24H2 / 25H2 Client multi-edition).
- ~25 GB free disk space for staging, mounting, and output.
- Internet access on the build host only when using `-PreDownloadApps` or when `tools/oscdimg.exe` must be downloaded.

---

## Quick Start

1. **Customize Settings (Optional)**
   Edit [config.json](config.json) to set your exact `"OSName"`, `"Manufacturer"`, `"TimeZone"`, debloat list, drivers, or app list.
2. **Add MeshCentral, Drivers & Wallpaper**
   - Place your MeshCentral executable at `apps\installers\meshagent64-NewPCS.exe` (or update `OfflineInstallers` in `config.json`).
   - Place your custom background image at `assets\wallpaper\wallpaper.jpg`.
   - Drop any `.inf` driver packs into `drivers\` (see [drivers/README.md](drivers/README.md)).
3. **Build the ISO**
   Either double-click [Build-ISO.cmd](Build-ISO.cmd), or open **PowerShell as Administrator** and run:
   ```powershell
   # Standard build (installs VC++ Redists, LibreWolf, TeamViewer online at first boot + offline meshagent.exe)
   .\Build-TinyWin11.ps1 -IsoPath "C:\Path\To\Win11.iso"

   # Pre-download VC++ Redists, LibreWolf, and TeamViewer into the ISO for 100% offline installation
   .\Build-TinyWin11.ps1 -IsoPath "C:\Path\To\Win11.iso" -PreDownloadApps

   # Build from an already-mounted ISO, picking the image index explicitly (e.g. 6 = Windows 11 Pro)
   .\Build-TinyWin11.ps1 -SourceDrive "E:" -Index 6

   # Fast rebuild: reuse the WIMs from the existing output ISO and only refresh
   # config.json, autounattend.xml, FirstLogon.ps1, SetupComplete.ps1, and bundled apps
   .\Build-TinyWin11.ps1 -QuickUpdateScripts
   ```
   If `-IsoPath`/`-SourceDrive` are omitted, the script auto-detects an ISO in `iso\` or prompts for a path. If `-Index` is omitted it auto-selects Windows 11 Pro.

### Parameters

| Parameter | Description |
| --- | --- |
| `-IsoPath` | Path to the source Windows 11 ISO. |
| `-SourceDrive` | Drive letter of an already-mounted ISO (e.g. `E:`). |
| `-Index` | WIM/ESD image index to build. Auto-selects Windows 11 Pro if omitted. |
| `-ConfigPath` | Alternate `config.json` path. |
| `-OutputIsoPath` | Output ISO path (default `output\POS_READY_2026.iso`). |
| `-WorkDir` | Working directory for DISM mounts and staging (default `work\`). |
| `-PreDownloadApps` | Bundle Winget app installers into the ISO for offline install. |
| `-QuickUpdateScripts` | Fast rebuild that reuses existing WIMs and only updates scripts/config/apps. |

---

## Output

The build writes `output\POS_READY_2026.iso` (UEFI + Legacy BIOS bootable) and `output\build.log`. Write the ISO to USB with Rufus/Ventoy or attach it directly to a VM (VirtIO drivers are pre-injected for KVM/Proxmox guests).
