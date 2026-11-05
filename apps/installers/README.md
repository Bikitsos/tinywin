# Bundled Offline Application Installers

Place your offline `.exe`, `.msi`, or `.msix` installers in this directory before running `Build-TinyWin11.ps1`.

## MeshCentral Agent (`meshagent.exe`)
1. Copy your MeshCentral agent installer into this folder and name it **`meshagent.exe`** (or update `FileName` in `config.json`).
2. By default, `config.json` is pre-configured to install `meshagent.exe` silently with `-fullinstall` during `SetupComplete` (as `SYSTEM` right before first logon) and verify the `Mesh Agent` service at `FirstLogon`.

## Other Offline Installers
Any additional `.msi`, `.msix`, or `.exe` files placed in this folder will also be bundled into the ISO (`C:\TinyWin\Apps\Installers`) and installed automatically during first logon when `"AutoInstallAllInFolder": true` is enabled in `config.json`.
