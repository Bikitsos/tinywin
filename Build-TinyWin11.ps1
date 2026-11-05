<#
.SYNOPSIS
    TinyWin 11 Custom ISO Builder (DISM-based).
    Builds a debloated, customized Windows 11 ISO with custom OS name/branding,
    regional & keyboard settings, custom wallpaper, hardware bypasses, and
    pre-installed applications (VC++ Redistributables, LibreWolf, TeamViewer, MeshCentral).

.EXAMPLE
    .\Build-TinyWin11.ps1 -IsoPath "C:\ISOs\Win11_24H2_English_x64.iso"
    .\Build-TinyWin11.ps1 -IsoPath "C:\ISOs\Win11.iso" -Index 6 -PreDownloadApps
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Path to the source Windows 11 ISO file.")]
    [string]$IsoPath,

    [Parameter(Mandatory = $false, HelpMessage = "Drive letter of an already mounted Windows 11 ISO (e.g. 'E:').")]
    [string]$SourceDrive,

    [Parameter(Mandatory = $false, HelpMessage = "WIM/ESD Image Index to build (e.g. 6 for Windows 11 Pro). Prompts if omitted.")]
    [int]$Index = 0,

    [Parameter(Mandatory = $false, HelpMessage = "Path to config.json.")]
    [string]$ConfigPath,

    [Parameter(Mandatory = $false, HelpMessage = "Output path for the custom ISO.")]
    [string]$OutputIsoPath,

    [Parameter(Mandatory = $false, HelpMessage = "Working directory for mounting WIMs and staging ISO files.")]
    [string]$WorkDir,

    [Parameter(Mandatory = $false, HelpMessage = "Pre-download VC++ Redistributables, LibreWolf, and TeamViewer into the ISO for 100% offline installation.")]
    [switch]$PreDownloadApps,

    [Parameter(Mandatory = $false, HelpMessage = "Fast 15-second rebuild: reuses existing output ISO's WIMs and only updates config.json, autounattend.xml, FirstLogon.ps1, SetupComplete.ps1, and bundled apps.")]
    [switch]$QuickUpdateScripts
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $PSScriptRoot "config.json"
}
if ([string]::IsNullOrWhiteSpace($OutputIsoPath)) {
    $OutputIsoPath = Join-Path $PSScriptRoot "output\POS_READY_2026.iso"
}
if ([string]::IsNullOrWhiteSpace($WorkDir)) {
    $WorkDir = Join-Path $PSScriptRoot "work"
}

# ---------------------------------------------------------------------------
# 0. Verify Administrator Privileges
# ---------------------------------------------------------------------------
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Build-TinyWin11.ps1 must be run as Administrator (required for DISM mount and offline registry editing)."
    exit 1
}

if (-not (Test-Path $ConfigPath)) {
    throw "Configuration file not found at: $ConfigPath"
}
$config = Get-Content -Path $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json

$logDir = Split-Path -Path $OutputIsoPath -Parent
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
Start-Transcript -Path (Join-Path $logDir "build.log") -Force | Out-Null

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "   TinyWin 11 Custom ISO Builder                                  " -ForegroundColor Cyan
Write-Host "   Target OS Name : $($config.Branding.OSName)                    " -ForegroundColor Cyan
Write-Host "   TimeZone       : $($config.Regional.TimeZone)                  " -ForegroundColor Cyan
Write-Host "   Input Locales  : $($config.Regional.InputLocale)               " -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Helper: Update WIM Image Name & Description via native Windows wimgapi.dll
# ---------------------------------------------------------------------------
function Set-WimImageMetadata {
    param(
        [string]$WimPath,
        [int]$ImageIndex = 1,
        [string]$NewName,
        [string]$NewDescription
    )
    try {
        if (-not ("TinyWin.WimApi" -as [type])) {
            Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace TinyWin {
    public static class WimApi {
        [DllImport("wimgapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern IntPtr WIMCreateFile(string pszWimPath, uint dwDesiredAccess, uint dwCreationDisposition, uint dwFlagsAndAttributes, uint dwCompressionType, out uint pdwCreationResult);

        [DllImport("wimgapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern bool WIMSetTemporaryPath(IntPtr hWim, string pszPath);

        [DllImport("wimgapi.dll", SetLastError = true)]
        public static extern IntPtr WIMLoadImage(IntPtr hWim, uint dwImageIndex);

        [DllImport("wimgapi.dll", SetLastError = true)]
        public static extern bool WIMGetImageInformation(IntPtr hImage, out IntPtr ppvImageInfo, out uint pcbImageInfo);

        [DllImport("wimgapi.dll", SetLastError = true)]
        public static extern bool WIMSetImageInformation(IntPtr hImage, IntPtr pvImageInfo, uint cbImageInfo);

        [DllImport("wimgapi.dll", SetLastError = true)]
        public static extern bool WIMCloseHandle(IntPtr hObject);
    }
}
"@
        }

        $WIM_GENERIC_READ  = 0x80000000L
        $WIM_GENERIC_WRITE = 0x40000000L
        $WIM_OPEN_EXISTING = 3
        $creationResult    = [uint32]0

        $access = [uint32]($WIM_GENERIC_READ -bor $WIM_GENERIC_WRITE)
        $hWim = [TinyWin.WimApi]::WIMCreateFile($WimPath, $access, $WIM_OPEN_EXISTING, 0, 0, [ref]$creationResult)
        if ($hWim -eq [IntPtr]::Zero) { return }

        try {
            [TinyWin.WimApi]::WIMSetTemporaryPath($hWim, $env:TEMP) | Out-Null
            $hImg = [TinyWin.WimApi]::WIMLoadImage($hWim, [uint32]$ImageIndex)
            if ($hImg -ne [IntPtr]::Zero) {
                try {
                    $pInfo = [IntPtr]::Zero
                    $cbInfo = [uint32]0
                    if ([TinyWin.WimApi]::WIMGetImageInformation($hImg, [ref]$pInfo, [ref]$cbInfo)) {
                        $xmlStr = [System.Runtime.InteropServices.Marshal]::PtrToStringUni($pInfo).TrimStart([char]0xFEFF)
                        $xmlDoc = [xml]$xmlStr
                        if ($xmlDoc.IMAGE) {
                            $xmlDoc.IMAGE.NAME = $NewName
                            $xmlDoc.IMAGE.DESCRIPTION = $NewDescription
                            if ($xmlDoc.IMAGE.DISPLAYNAME) { $xmlDoc.IMAGE.DISPLAYNAME = $NewName }
                            if ($xmlDoc.IMAGE.DISPLAYDESCRIPTION) { $xmlDoc.IMAGE.DISPLAYDESCRIPTION = $NewDescription }

                            $updatedXml = ([char]0xFEFF) + $xmlDoc.OuterXml + "`0"
                            $bytes = [System.Text.Encoding]::Unicode.GetBytes($updatedXml)
                            $pNew = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($bytes.Length)
                            try {
                                [System.Runtime.InteropServices.Marshal]::Copy($bytes, 0, $pNew, $bytes.Length)
                                [TinyWin.WimApi]::WIMSetImageInformation($hImg, $pNew, [uint32]$bytes.Length) | Out-Null
                                Write-Host "    [+] Updated WIM Image Name to '$NewName'" -ForegroundColor Green
                            } finally {
                                [System.Runtime.InteropServices.Marshal]::FreeHGlobal($pNew)
                            }
                        }
                    }
                } finally {
                    [TinyWin.WimApi]::WIMCloseHandle($hImg) | Out-Null
                }
            }
        } finally {
            [TinyWin.WimApi]::WIMCloseHandle($hWim) | Out-Null
        }
    } catch {
        Write-Warning "    Could not update WIM display metadata: $_"
    }
}

# ---------------------------------------------------------------------------
# Helper: Take Ownership & Grant Administrators Full Control on Offline Path
# ---------------------------------------------------------------------------
function Unlock-OfflinePath {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        if ($item -and $item.PSIsContainer) {
            takeown.exe /F "$Path" /R /A /D Y 2>$null | Out-Null
            icacls.exe "$Path" /grant "Administrators:(F)" /T /C /Q 2>$null | Out-Null
        } else {
            takeown.exe /F "$Path" /A 2>$null | Out-Null
            icacls.exe "$Path" /grant "Administrators:(F)" /C /Q 2>$null | Out-Null
        }
    }
}

# ---------------------------------------------------------------------------
# Helper: Take ownership + grant Administrators Full Control on an offline
# registry key (TrustedInstaller-only keys such as Services\TrkWks).
# ---------------------------------------------------------------------------
function Enable-TokenPrivilege {
    param([string]$Privilege)
    if (-not ("TinyWinPriv" -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class TinyWinPriv {
    [StructLayout(LayoutKind.Sequential)] struct LUID { public uint LowPart; public int HighPart; }
    [StructLayout(LayoutKind.Sequential)] struct TOKEN_PRIVILEGES { public int Count; public LUID Luid; public int Attr; }
    [DllImport("advapi32.dll", SetLastError = true)] static extern bool OpenProcessToken(IntPtr h, int acc, ref IntPtr tok);
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool LookupPrivilegeValue(string host, string name, ref LUID luid);
    [DllImport("advapi32.dll", SetLastError = true)] static extern bool AdjustTokenPrivileges(IntPtr tok, bool disall, ref TOKEN_PRIVILEGES newst, int len, IntPtr prev, IntPtr ret);
    [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
    public static bool Enable(string priv) {
        IntPtr tok = IntPtr.Zero;
        if (!OpenProcessToken(GetCurrentProcess(), 0x28, ref tok)) return false;
        TOKEN_PRIVILEGES tp = new TOKEN_PRIVILEGES(); tp.Count = 1; tp.Attr = 2;
        if (!LookupPrivilegeValue(null, priv, ref tp.Luid)) return false;
        return AdjustTokenPrivileges(tok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
    }
}
"@
    }
    [TinyWinPriv]::Enable($Privilege) | Out-Null
}

function Unlock-OfflineRegKey {
    param([string]$KeyPath)   # e.g. HKLM\zSYSTEM\ControlSet001\Services\TrkWks
    $sub = $KeyPath -replace '^HKLM\\', ''
    Enable-TokenPrivilege "SeTakeOwnershipPrivilege"
    Enable-TokenPrivilege "SeRestorePrivilege"
    $admins = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)
    try {
        # Walk up to the nearest existing key (reg add may be creating a new subkey under a locked parent)
        $key = $null
        while ($sub -and -not $key) {
            $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($sub, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, [System.Security.AccessControl.RegistryRights]::TakeOwnership)
            if (-not $key) { $sub = Split-Path $sub -Parent }
        }
        if (-not $key) { return $false }
        $acl = $key.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Owner)
        $acl.SetOwner($admins)
        $key.SetAccessControl($acl)
        $key.Close()

        $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($sub, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, [System.Security.AccessControl.RegistryRights]::ChangePermissions)
        $acl = $key.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
        $rule = New-Object System.Security.AccessControl.RegistryAccessRule($admins, "FullControl", "ContainerInherit", "None", "Allow")
        $acl.AddAccessRule($rule)
        $key.SetAccessControl($acl)
        $key.Close()
        return $true
    } catch {
        return $false
    }
}

# ---------------------------------------------------------------------------
# Helper: Shadow reg.exe so failing offline-hive operations report the exact
# command that failed (the raw calls below are piped to Out-Null and would
# otherwise only print a bare "ERROR: Access is denied."). On Access Denied
# against a loaded offline hive, unlock the key and retry once.
# ---------------------------------------------------------------------------
function reg.exe {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$RegArgs)
    $ErrorActionPreference = "Continue"   # avoid NativeCommandError on 2>&1 in PS 5.1
    $output = & "$env:SystemRoot\System32\reg.exe" @RegArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        $msg = (($output | ForEach-Object { "$_" }) -join " ").Trim()
        if ($msg -match "Access is denied" -and $RegArgs.Count -ge 2 -and $RegArgs[0] -in @("add", "delete") -and $RegArgs[1] -like "HKLM\z*") {
            if (Unlock-OfflineRegKey -KeyPath $RegArgs[1]) {
                $output = & "$env:SystemRoot\System32\reg.exe" @RegArgs 2>&1
                $msg = (($output | ForEach-Object { "$_" }) -join " ").Trim()
            }
        }
        if ($LASTEXITCODE -ne 0 -and $msg -notmatch "unable to find") {   # "unable to find" is expected for delete-if-exists calls
            Write-Host "    [!] reg.exe $($RegArgs -join ' ')" -ForegroundColor Red
            Write-Host "        $msg" -ForegroundColor Red
        }
    }
    $output
}

# ---------------------------------------------------------------------------
# 1. Locate Source ISO or Drive & Stage ISO Files
# ---------------------------------------------------------------------------
if ($QuickUpdateScripts) {
    if (-not (Test-Path $OutputIsoPath)) {
        throw "-QuickUpdateScripts requires an existing built ISO at '$OutputIsoPath'. Run a full build first."
    }
    $IsoPath = $OutputIsoPath
    Write-Host "[+] Fast Rebuild Mode (-QuickUpdateScripts): Reusing existing WIMs from $OutputIsoPath" -ForegroundColor Green
} elseif ([string]::IsNullOrWhiteSpace($IsoPath) -and [string]::IsNullOrWhiteSpace($SourceDrive)) {
    # Auto-detect any .iso placed in .\iso\ or project root
    $autoIso = Get-ChildItem -Path @((Join-Path $PSScriptRoot "iso"), $PSScriptRoot) -Filter "*.iso" -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($autoIso) {
        $IsoPath = $autoIso.FullName
        Write-Host "[+] Auto-detected Windows ISO: $IsoPath" -ForegroundColor Green
    } else {
        $IsoPath = Read-Host "Enter full path to your Windows 11 ISO file (or mounted drive letter like E:)"
        if ($IsoPath -match "^[a-zA-Z]:\\?$") {
            $SourceDrive = $IsoPath.Substring(0, 2)
            $IsoPath = $null
        }
    }
}

$IsoStageDir = Join-Path $WorkDir "ISO"
$MountDir    = Join-Path $WorkDir "mount"
$BootMount   = Join-Path $WorkDir "boot_mount"

# Clean previous working directories if any
foreach ($dir in @($MountDir, $BootMount)) {
    if (Test-Path $dir) {
        dism.exe /Unmount-Image /MountDir:"$dir" /Discard 2>$null | Out-Null
    }
}
if (Test-Path $WorkDir) {
    Write-Host "[*] Cleaning previous working directory: $WorkDir" -ForegroundColor Gray
    Remove-Item -Path $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path $IsoStageDir -Force | Out-Null
New-Item -ItemType Directory -Path $MountDir -Force | Out-Null
New-Item -ItemType Directory -Path $BootMount -Force | Out-Null

$mountedIso = $null
try {
    if (-not [string]::IsNullOrWhiteSpace($IsoPath)) {
        $IsoPath = $IsoPath.Trim('"')
        if (-not (Test-Path $IsoPath)) {
            throw "ISO file not found at: $IsoPath"
        }
        Write-Host "`n[1/9] Mounting source ISO: $IsoPath..." -ForegroundColor Yellow
        $mountResult = Mount-DiskImage -ImagePath $IsoPath -PassThru
        $mountedIso = $mountResult
        $driveLetter = ($mountResult | Get-Volume).DriveLetter
        $SourceDrive = "${driveLetter}:"
    }

    $SourceDrive = $SourceDrive.TrimEnd('\')
    if (-not (Test-Path "$SourceDrive\sources\boot.wim")) {
        throw "Invalid Windows installation source at $SourceDrive (sources\boot.wim not found)."
    }

    Write-Host "[*] Copying ISO contents from $SourceDrive to staging folder ($IsoStageDir)..." -ForegroundColor Cyan
    Copy-Item -Path "$SourceDrive\*" -Destination $IsoStageDir -Recurse -Force
    # Remove Read-Only attribute on copied files
    Get-ChildItem -Path $IsoStageDir -Recurse -Force | ForEach-Object {
        if ($_.Attributes -band [System.IO.FileAttributes]::ReadOnly) {
            $_.Attributes = $_.Attributes -bxor [System.IO.FileAttributes]::ReadOnly
        }
    }
} finally {
    if ($mountedIso) {
        Write-Host "[*] Dismounting source ISO..." -ForegroundColor Gray
        Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue | Out-Null
    }
}

# ---------------------------------------------------------------------------
# 2. Select Windows Edition Index & Export Single-Index install.wim
# ---------------------------------------------------------------------------
if (-not $QuickUpdateScripts) {
Write-Host "`n[2/9] Inspecting Windows Image (install.wim / install.esd)..." -ForegroundColor Yellow

$wimPath = Join-Path $IsoStageDir "sources\install.wim"
$esdPath = Join-Path $IsoStageDir "sources\install.esd"
$sourceImageFile = if (Test-Path $wimPath) { $wimPath } elseif (Test-Path $esdPath) { $esdPath } else { throw "Neither install.wim nor install.esd found in sources folder." }

$images = Get-WindowsImage -ImagePath $sourceImageFile
Write-Host "`nAvailable Windows Editions:" -ForegroundColor Cyan
foreach ($img in $images) {
    Write-Host ("  [{0}] {1} ({2:N2} GB)" -f $img.ImageIndex, $img.ImageName, ($img.ImageSize / 1GB))
}

if ($Index -le 0) {
    $proImg = $images | Where-Object { $_.ImageName -eq "Windows 11 Pro" } | Select-Object -First 1
    if ($proImg) {
        $Index = [int]$proImg.ImageIndex
        Write-Host "`n[+] Auto-selected ImageIndex $Index (Windows 11 Pro)" -ForegroundColor Green
    } else {
        $selected = Read-Host "`nSelect the ImageIndex to customize (e.g. enter index for Windows 11 Pro)"
        $Index = [int]$selected
    }
}

if (-not ($images | Where-Object { $_.ImageIndex -eq $Index })) {
    throw "Invalid ImageIndex: $Index"
}

$tempWim = Join-Path $WorkDir "install_single.wim"
Write-Host "[*] Exporting Index $Index to working WIM ($tempWim)..." -ForegroundColor Cyan
dism.exe /Export-Image /SourceImageFile:"$sourceImageFile" /SourceIndex:$Index /DestinationImageFile:"$tempWim" /Compress:fast /CheckIntegrity
if ($LASTEXITCODE -ne 0) { throw "Failed to export image index $Index." }

Remove-Item -Path $sourceImageFile -Force
Move-Item -Path $tempWim -Destination $wimPath -Force

# ---------------------------------------------------------------------------
# 3. Mount install.wim & Remove Bloatware Appx / Capabilities / Features
# ---------------------------------------------------------------------------
Write-Host "`n[3/9] Mounting install.wim to $MountDir..." -ForegroundColor Yellow
dism.exe /Mount-Image /ImageFile:"$wimPath" /Index:1 /MountDir:"$MountDir"
if ($LASTEXITCODE -ne 0) { throw "Failed to mount install.wim." }

Write-Host "`n[4/9] Removing Provisioned Bloatware Appx Packages, Capabilities & Features..." -ForegroundColor Yellow

# 4a. Provisioned Appx Packages
# Note: Microsoft.WindowsStore, StorePurchaseApp, and MicrosoftWindows.Client.WebExperience are
# kept intact during offline servicing so Windows 11 OOBE (CloudExperienceHost) completes cleanly,
# and Microsoft Store is removed automatically in FirstLogon.ps1 right after OOBE finishes.
$provisioned = Get-AppxProvisionedPackage -Path $MountDir
$removedCount = 0
$keptCount = 0
$oobeProtected = @("Microsoft.WindowsStore", "Microsoft.StorePurchaseApp", "MicrosoftWindows.Client.WebExperience")

foreach ($pkg in $provisioned) {
    $shouldRemove = $false
    $isOobeProtected = $false
    foreach ($prot in $oobeProtected) {
        if ($pkg.DisplayName -like "*$prot*" -or $pkg.PackageName -like "*$prot*") {
            $isOobeProtected = $true
            break
        }
    }

    if (-not $isOobeProtected) {
        if ($config.Debloat.RemoveAllStoreAppsExceptKept -and $config.Debloat.AppxPackagesToKeep) {
            $shouldRemove = $true
            foreach ($keepPattern in $config.Debloat.AppxPackagesToKeep) {
                if ($pkg.DisplayName -like "*$keepPattern*" -or $pkg.PackageName -like "*$keepPattern*") {
                    $shouldRemove = $false
                    break
                }
            }
        } else {
            foreach ($pattern in $config.Debloat.AppxPackagesToRemove) {
                if ($pkg.DisplayName -like "*$pattern*" -or $pkg.PackageName -like "*$pattern*") {
                    $shouldRemove = $true
                    break
                }
            }
        }
    }

    if ($shouldRemove) {
        Write-Host "    [-] Removing Appx: $($pkg.DisplayName)" -ForegroundColor Gray
        Remove-AppxProvisionedPackage -Path $MountDir -PackageName $pkg.PackageName -ErrorAction SilentlyContinue | Out-Null
        $removedCount++
    } else {
        Write-Host "    [+] Keeping Appx: $($pkg.DisplayName)" -ForegroundColor DarkGreen
        $keptCount++
    }
}
Write-Host "    [+] Removed $removedCount bloatware Appx packages (kept $keptCount packages; Store removed post-OOBE)." -ForegroundColor Green

# Clear Default User Start Menu LayoutModification.json so no stub apps are pinned on first logon
if ($config.Debloat.ClearStartMenuPinnedAds) {
    $defaultShellDir = Join-Path $MountDir "Users\Default\AppData\Local\Microsoft\Windows\Shell"
    if (-not (Test-Path $defaultShellDir)) {
        New-Item -ItemType Directory -Path $defaultShellDir -Force | Out-Null
    }
    Set-Content -Path (Join-Path $defaultShellDir "LayoutModification.json") -Value '{"pinnedList":[]}' -Encoding UTF8 -Force
}

# 4b. Capabilities
$installedCaps = Get-WindowsCapability -Path $MountDir | Where-Object { $_.State -eq "Installed" }
foreach ($cap in $installedCaps) {
    foreach ($pattern in $config.Debloat.CapabilitiesToRemove) {
        if ($cap.Name -like "$pattern*") {
            Write-Host "    [-] Removing Capability: $($cap.Name)" -ForegroundColor Gray
            Remove-WindowsCapability -Path $MountDir -Name $cap.Name -ErrorAction SilentlyContinue | Out-Null
            break
        }
    }
}

# 4c. Optional Features (Recall, WorkFolders, etc.)
foreach ($featName in $config.Debloat.FeaturesToDisable) {
    $feat = Get-WindowsOptionalFeature -Path $MountDir -FeatureName $featName -ErrorAction SilentlyContinue
    if ($feat -and $feat.State -eq "Enabled") {
        Write-Host "    [-] Disabling Feature: $featName" -ForegroundColor Gray
        Disable-WindowsOptionalFeature -Path $MountDir -FeatureName $featName -Remove -NoRestart -ErrorAction SilentlyContinue | Out-Null
    }
}

# 4c-POS. Enable .NET Framework 3.5 (NetFx3) from ISO sources\sxs for legacy POS software & printer drivers
if ($config.POSOptimizations -and $config.POSOptimizations.EnableDotNet35) {
    $sxsDir = Join-Path $IsoStageDir "sources\sxs"
    if (Test-Path $sxsDir) {
        Write-Host "    [+] Enabling .NET Framework 3.5 (NetFx3) from $sxsDir..." -ForegroundColor Cyan
        dism.exe /Image:"$MountDir" /Enable-Feature /FeatureName:NetFx3 /All /LimitAccess /Source:"$sxsDir"
    }
}

# 4d. Remove Microsoft Edge (while keeping EdgeCore/EdgeWebView2 runtime & SystemApps Inbox registration intact for OOBE)
if ($config.Debloat.RemoveEdge) {
    Write-Host "    [-] Removing Microsoft Edge browser (preserving WebView2 Runtime)..." -ForegroundColor Cyan
    $edgePaths = @(
        (Join-Path $MountDir "Program Files (x86)\Microsoft\Edge"),
        (Join-Path $MountDir "Program Files (x86)\Microsoft\EdgeUpdate")
    )
    foreach ($ep in $edgePaths) {
        if (Test-Path $ep) {
            Unlock-OfflinePath -Path $ep
            Remove-Item -Path $ep -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# 4e. Remove OneDrive
if ($config.Debloat.RemoveOneDrive) {
    Write-Host "    [-] Removing OneDrive installer binaries..." -ForegroundColor Cyan
    $oneDrivePaths = @(
        (Join-Path $MountDir "Windows\System32\OneDriveSetup.exe"),
        (Join-Path $MountDir "Windows\SysWOW64\OneDriveSetup.exe")
    )
    foreach ($odp in $oneDrivePaths) {
        if (Test-Path $odp) {
            Unlock-OfflinePath -Path $odp
            Remove-Item -Path $odp -Force -ErrorAction SilentlyContinue
        }
    }
}

# 4e-2. Strip dead Edge/OneDrive/Outlook shortcuts from Default User, Public & All Users profiles
if ($config.POSOptimizations -and $config.POSOptimizations.CleanDefaultUserShortcuts) {
    $lnkDirs = @(
        (Join-Path $MountDir "Users\Default\Desktop"),
        (Join-Path $MountDir "Users\Public\Desktop"),
        (Join-Path $MountDir "Users\Default\AppData\Roaming\Microsoft\Windows\Start Menu\Programs"),
        (Join-Path $MountDir "ProgramData\Microsoft\Windows\Start Menu\Programs")
    )
    foreach ($ld in $lnkDirs) {
        if (Test-Path $ld) {
            Get-ChildItem -Path $ld -Filter "*.lnk" -File -ErrorAction SilentlyContinue |
                Where-Object { $_.BaseName -match "Edge|OneDrive|Outlook|Teams|Copilot|Store" } |
                ForEach-Object {
                    Unlock-OfflinePath -Path $_.FullName
                    Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
                }
        }
    }
}

# 4f. Inject Offline INF Drivers (drivers\VirtIO, drivers\Intel_POS_Common, drivers\CQ-JY12-N150, etc.) into Windows DriverStore
if ($config.Drivers -and $config.Drivers.InjectDriversIntoInstallWim) {
    Write-Host "    [*] Injecting signed INF Drivers into Windows DriverStore (no .exe/.msi bloatware installers)..." -ForegroundColor Cyan

    $driversRoot = if ($config.Drivers.DriversRootFolder) { Join-Path $PSScriptRoot $config.Drivers.DriversRootFolder } else { Join-Path $PSScriptRoot "drivers" }
    if (Test-Path $driversRoot) {
        $driverPacks = Get-ChildItem -Path $driversRoot -Directory -ErrorAction SilentlyContinue
        foreach ($pack in $driverPacks) {
            $infCount = (Get-ChildItem -Path $pack.FullName -Recurse -Filter "*.inf" -ErrorAction SilentlyContinue).Count
            if ($infCount -gt 0) {
                Write-Host "        [*] Injecting driver pack '$($pack.Name)' ($infCount INF files)..." -ForegroundColor Cyan
                dism.exe /Image:"$MountDir" /Add-Driver /Driver:"$($pack.FullName)" /Recurse
                Write-Host "        [+] Completed driver pack '$($pack.Name)'." -ForegroundColor Green
            }
        }
    }
}

# ---------------------------------------------------------------------------
# 5. Inject Custom Wallpaper into Offline Image
# ---------------------------------------------------------------------------
Write-Host "`n[5/9] Applying Custom Background Wallpaper..." -ForegroundColor Yellow

$wallpaperRelPath = $config.Customization.CustomWallpaperPath
$wallpaperFullPath = if ([System.IO.Path]::IsPathRooted($wallpaperRelPath)) { $wallpaperRelPath } else { Join-Path $PSScriptRoot $wallpaperRelPath }

if (Test-Path $wallpaperFullPath) {
    Write-Host "    [+] Found custom wallpaper: $wallpaperFullPath" -ForegroundColor Green
    $winWallDir = Join-Path $MountDir "Windows\Web\Wallpaper\Windows"
    $win4kDir   = Join-Path $MountDir "Windows\Web\4K\Wallpaper\Windows"

    # Copy as tinywin_wallpaper.jpg (and .png if present) and also replace img0.jpg (Light) & img19.jpg (Dark)
    Copy-Item -Path $wallpaperFullPath -Destination (Join-Path $winWallDir "tinywin_wallpaper.jpg") -Force
    $pngSibling = [System.IO.Path]::ChangeExtension($wallpaperFullPath, ".png")
    if (Test-Path $pngSibling) {
        Copy-Item -Path $pngSibling -Destination (Join-Path $winWallDir "tinywin_wallpaper.png") -Force
    }
    foreach ($defaultImg in @("img0.jpg", "img19.jpg")) {
        $targetImg = Join-Path $winWallDir $defaultImg
        if (Test-Path $targetImg) {
            Unlock-OfflinePath -Path $targetImg
            Copy-Item -Path $wallpaperFullPath -Destination $targetImg -Force
        }
    }
    if (Test-Path $win4kDir) {
        Unlock-OfflinePath -Path $win4kDir
        Get-ChildItem -Path $win4kDir -Filter "*.jpg" -ErrorAction SilentlyContinue | ForEach-Object {
            Unlock-OfflinePath -Path $_.FullName
            Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
        }
    }
} else {
    Write-Host "    [i] No custom wallpaper file found at '$wallpaperFullPath'. Keeping default wallpaper (you can place a JPG there before building)." -ForegroundColor DarkYellow
}

# ---------------------------------------------------------------------------
# 6. Offline Registry Modifications (Branding, Bypasses, Telemetry, Regional)
# ---------------------------------------------------------------------------
Write-Host "`n[6/9] Modifying Offline Registry Hives..." -ForegroundColor Yellow

reg.exe load HKLM\zCOMPONENTS "$MountDir\Windows\System32\config\COMPONENTS" | Out-Null
reg.exe load HKLM\zDEFAULT    "$MountDir\Windows\System32\config\default"    | Out-Null
reg.exe load HKLM\zNTUSER     "$MountDir\Users\Default\NTUSER.DAT"           | Out-Null
reg.exe load HKLM\zSOFTWARE   "$MountDir\Windows\System32\config\SOFTWARE"   | Out-Null
reg.exe load HKLM\zSYSTEM     "$MountDir\Windows\System32\config\SYSTEM"     | Out-Null

try {
    # 6a. Custom OS Branding & OEM Info
    $osName = $config.Branding.OSName
    $mfg    = $config.Branding.Manufacturer
    $model  = $config.Branding.Model
    reg.exe add "HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation" /v Manufacturer /t REG_SZ /d "$mfg" /f | Out-Null
    reg.exe add "HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation" /v Model /t REG_SZ /d "$model" /f | Out-Null
    reg.exe add "HKLM\zSOFTWARE\Microsoft\Windows NT\CurrentVersion" /v ProductName /t REG_SZ /d "$osName" /f | Out-Null
    reg.exe add "HKLM\zSOFTWARE\Microsoft\Windows NT\CurrentVersion" /v RegisteredOrganization /t REG_SZ /d "$mfg" /f | Out-Null

    # 6b. Hardware Requirement Bypasses
    if ($config.Bypasses.BypassTPMAndSecureBoot) {
        reg.exe add "HKLM\zSYSTEM\Setup\LabConfig" /v BypassTPMCheck /t REG_DWORD /d 1 /f | Out-Null
        reg.exe add "HKLM\zSYSTEM\Setup\LabConfig" /v BypassSecureBootCheck /t REG_DWORD /d 1 /f | Out-Null
        reg.exe add "HKLM\zSYSTEM\Setup\MoSetup" /v AllowUpgradesWithUnsupportedTPMOrCPU /t REG_DWORD /d 1 /f | Out-Null
    }
    if ($config.Bypasses.BypassRAMCheck) {
        reg.exe add "HKLM\zSYSTEM\Setup\LabConfig" /v BypassRAMCheck /t REG_DWORD /d 1 /f | Out-Null
    }
    if ($config.Bypasses.BypassCPUCheck) {
        reg.exe add "HKLM\zSYSTEM\Setup\LabConfig" /v BypassCPUCheck /t REG_DWORD /d 1 /f | Out-Null
    }
    if ($config.Bypasses.BypassStorageCheck) {
        reg.exe add "HKLM\zSYSTEM\Setup\LabConfig" /v BypassStorageCheck /t REG_DWORD /d 1 /f | Out-Null
    }
    if ($config.Bypasses.BypassMicrosoftAccount) {
        reg.exe add "HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" /v BypassNRO /t REG_DWORD /d 1 /f | Out-Null
    }
    if ($config.Bypasses.DisableBitLockerAutoEncryption) {
        reg.exe add "HKLM\zSYSTEM\ControlSet001\Control\BitLocker" /v PreventDeviceEncryption /t REG_DWORD /d 1 /f | Out-Null
    }

    # 6c. Remove OneDrive Auto-Run from Default User
    if ($config.Debloat.RemoveOneDrive) {
        reg.exe delete "HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Run" /v OneDriveSetup /f 2>$null | Out-Null
    }

    # 6c-2. Edge updater service removal, service disabling (ServicesToDisable), Ndu, pagefile and NTFS tweaks are
    #       deliberately NOT applied offline: changing SYSTEM-hive service state before OOBE has run can trip
    #       CloudExperienceHost ("Why did my PC restart?"). SetupComplete.ps1 applies them post-OOBE instead.

    # 6c-4. Windows Update Orchestrator re-installs new Outlook / Dev Home after OOBE even if the Appx was removed offline
    foreach ($uso in @("OutlookUpdate", "DevHomeUpdate")) {
        reg.exe delete "HKLM\zSOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe" /v $uso /f 2>$null | Out-Null
    }

    # 6d. Disable Telemetry, Sponsored Apps, Copilot & Recall (OOBE-safe subset; Store removal runs in FirstLogon.ps1 after OOBE)
    if ($config.Debloat.ClearStartMenuPinnedAds) {
        $startPolicyKey = "HKLM\zSOFTWARE\Microsoft\PolicyManager\current\device\Start"
        $startProviderKey = "HKLM\zSOFTWARE\Microsoft\PolicyManager\providers\B5292708-1619-419B-9923-E5D9F3925E71\default\Device\Start"
        reg.exe add $startPolicyKey /v ConfigureStartPins /t REG_SZ /d "{\`"pinnedList\`":[]}" /f 2>$null | Out-Null
        reg.exe add $startPolicyKey /v ConfigureStartPins_ProviderSet /t REG_DWORD /d 1 /f 2>$null | Out-Null
        reg.exe add $startPolicyKey /v ConfigureStartPins_WinningProvider /t REG_SZ /d "B5292708-1619-419B-9923-E5D9F3925E71" /f 2>$null | Out-Null
        reg.exe add $startProviderKey /v ConfigureStartPins /t REG_SZ /d "{\`"pinnedList\`":[]}" /f 2>$null | Out-Null
        reg.exe add $startProviderKey /v ConfigureStartPins_LastWrite /t REG_DWORD /d 1 /f 2>$null | Out-Null
        reg.exe add $startPolicyKey /v HideRecommendedSection /t REG_DWORD /d 1 /f 2>$null | Out-Null
        reg.exe add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\Explorer" /v ConfigureStartPinsJSON /t REG_SZ /d "{\`"pinnedList\`":[]}" /f 2>$null | Out-Null
        reg.exe add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\Explorer" /v HideRecommendedSection /t REG_DWORD /d 1 /f 2>$null | Out-Null
        reg.exe add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\Explorer" /v HideRecommendedPersonalizedSites /t REG_DWORD /d 1 /f 2>$null | Out-Null
        reg.exe add "HKLM\zNTUSER\Software\Policies\Microsoft\Windows\Explorer" /v ConfigureStartPinsJSON /t REG_SZ /d "{\`"pinnedList\`":[]}" /f 2>$null | Out-Null
        reg.exe add "HKLM\zNTUSER\Software\Policies\Microsoft\Windows\Explorer" /v HideRecommendedSection /t REG_DWORD /d 1 /f 2>$null | Out-Null
        reg.exe add "HKLM\zNTUSER\Software\Policies\Microsoft\Windows\Explorer" /v HideRecommendedPersonalizedSites /t REG_DWORD /d 1 /f 2>$null | Out-Null
    }

    if ($config.Debloat.DisableTelemetryAndAds) {
        reg.exe add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /t REG_DWORD /d 0 /f 2>$null | Out-Null
        reg.exe add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\DataCollection" /v DoNotShowFeedbackNotifications /t REG_DWORD /d 1 /f | Out-Null
        reg.exe add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\DataCollection" /v AllowDeviceNameInTelemetry /t REG_DWORD /d 0 /f | Out-Null
        reg.exe add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\DataCollection" /v LimitDiagnosticLogCollection /t REG_DWORD /d 1 /f | Out-Null
        reg.exe add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\DataCollection" /v LimitDumpCollection /t REG_DWORD /d 1 /f | Out-Null
        reg.exe add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\AppCompat" /v AITEnable /t REG_DWORD /d 0 /f | Out-Null
        reg.exe add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\AppCompat" /v DisableInventory /t REG_DWORD /d 1 /f | Out-Null
        reg.exe add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" /v DisabledByGroupPolicy /t REG_DWORD /d 1 /f | Out-Null
        reg.exe add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\System" /v EnableActivityFeed /t REG_DWORD /d 0 /f | Out-Null
        reg.exe add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\System" /v PublishUserActivities /t REG_DWORD /d 0 /f | Out-Null
        reg.exe add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\System" /v UploadUserActivities /t REG_DWORD /d 0 /f | Out-Null
        reg.exe add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\TextInput" /v AllowLinguisticDataCollection /t REG_DWORD /d 0 /f | Out-Null
        reg.exe add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent" /v DisableWindowsConsumerFeatures /t REG_DWORD /d 1 /f 2>$null | Out-Null
        reg.exe add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent" /v DisableSoftLanding /t REG_DWORD /d 1 /f 2>$null | Out-Null
        reg.exe add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent" /v DisableCloudOptimizedContent /t REG_DWORD /d 1 /f | Out-Null
        reg.exe add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent" /v DisableConsumerAccountStateContent /t REG_DWORD /d 1 /f | Out-Null
        reg.exe add "HKLM\zSOFTWARE\Policies\Microsoft\Dsh" /v AllowNewsAndInterests /t REG_DWORD /d 0 /f 2>$null | Out-Null
        reg.exe add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Search" /v AllowCortana /t REG_DWORD /d 0 /f | Out-Null
        reg.exe add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Search" /v DisableWebSearch /t REG_DWORD /d 1 /f | Out-Null
        reg.exe add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Search" /v ConnectedSearchUseWeb /t REG_DWORD /d 0 /f | Out-Null
        reg.exe add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Search" /v EnableDynamicContentInWSB /t REG_DWORD /d 0 /f | Out-Null
        reg.exe add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\GameDVR" /v AllowGameDVR /t REG_DWORD /d 0 /f | Out-Null
        reg.exe add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\Explorer" /v SettingsPageVisibility /t REG_SZ /d "hide:home;backup" /f | Out-Null

        reg.exe add "HKLM\zNTUSER\Software\Microsoft\InputPersonalization" /v RestrictImplicitInkCollection /t REG_DWORD /d 1 /f | Out-Null
        reg.exe add "HKLM\zNTUSER\Software\Microsoft\InputPersonalization" /v RestrictImplicitTextCollection /t REG_DWORD /d 1 /f | Out-Null
        reg.exe add "HKLM\zNTUSER\Software\Microsoft\Siuf\Rules" /v NumberOfSIUFInPeriod /t REG_DWORD /d 0 /f | Out-Null
        reg.exe add "HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" /v Enabled /t REG_DWORD /d 0 /f | Out-Null
        reg.exe add "HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Privacy" /v TailoredExperiencesWithDiagnosticDataEnabled /t REG_DWORD /d 0 /f | Out-Null
        reg.exe add "HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v Start_IrisRecommendations /t REG_DWORD /d 0 /f | Out-Null
        reg.exe add "HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v Start_AccountNotifications /t REG_DWORD /d 0 /f | Out-Null
        reg.exe add "HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowSyncProviderNotifications /t REG_DWORD /d 0 /f | Out-Null
        reg.exe add "HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\SmartActionPlatform\SmartClipboard" /v Disabled /t REG_DWORD /d 1 /f | Out-Null

        $cdmKey = "HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
        $cdmValues = @(
            "ContentDeliveryAllowed",
            "FeatureManagementEnabled",
            "OemPreInstalledAppsEnabled",
            "PreInstalledAppsEnabled",
            "PreInstalledAppsEverEnabled",
            "SilentInstalledAppsEnabled",
            "SoftLandingEnabled",
            "SubscribedContentEnabled",
            "SubscribedContent-310093Enabled",
            "SubscribedContent-314559Enabled",
            "SubscribedContent-314563Enabled",
            "SubscribedContent-338380Enabled",
            "SubscribedContent-338387Enabled",
            "SubscribedContent-338388Enabled",
            "SubscribedContent-338389Enabled",
            "SubscribedContent-338393Enabled",
            "SubscribedContent-353694Enabled",
            "SubscribedContent-353696Enabled",
            "SubscribedContent-353698Enabled",
            "SubscribedContent-88000326Enabled",
            "SystemPaneSuggestionsEnabled",
            "RotatingLockScreenEnabled",
            "RotatingLockScreenOverlayEnabled"
        )
        foreach ($val in $cdmValues) {
            reg.exe add $cdmKey /v $val /t REG_DWORD /d 0 /f | Out-Null
        }
    }

    if ($config.Debloat.RemoveCopilotAndRecall) {
        reg.exe add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" /v TurnOffWindowsCopilot /t REG_DWORD /d 1 /f | Out-Null
        reg.exe add "HKLM\zNTUSER\Software\Policies\Microsoft\Windows\WindowsCopilot" /v TurnOffWindowsCopilot /t REG_DWORD /d 1 /f | Out-Null
        reg.exe add "HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowCopilotButton /t REG_DWORD /d 0 /f | Out-Null
        foreach ($aiHive in @("HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsAI", "HKLM\zNTUSER\Software\Policies\Microsoft\Windows\WindowsAI")) {
            reg.exe add $aiHive /v DisableAIDataAnalysis /t REG_DWORD /d 1 /f | Out-Null
            reg.exe add $aiHive /v TurnOffSavingSnapshots /t REG_DWORD /d 1 /f | Out-Null
            reg.exe add $aiHive /v AllowRecallEnablement /t REG_DWORD /d 0 /f | Out-Null
            reg.exe add $aiHive /v DisableClickToDo /t REG_DWORD /d 1 /f | Out-Null
            reg.exe add $aiHive /v DisableCocreator /t REG_DWORD /d 1 /f | Out-Null
            reg.exe add $aiHive /v DisableGenerativeFill /t REG_DWORD /d 1 /f | Out-Null
            reg.exe add $aiHive /v DisableImageCreator /t REG_DWORD /d 1 /f | Out-Null
        }
        reg.exe add "HKLM\zNTUSER\Software\Policies\WindowsNotepad" /v DisableAIFeatures /t REG_DWORD /d 1 /f | Out-Null
    }

    # 6e. Default User Wallpaper & Classic Windows 7 UI Customization
    if (Test-Path $wallpaperFullPath) {
        reg.exe add "HKLM\zNTUSER\Control Panel\Desktop" /v Wallpaper /t REG_SZ /d "C:\Windows\Web\Wallpaper\Windows\tinywin_wallpaper.jpg" /f | Out-Null
    }
    if ($config.Customization.DarkModeDefault) {
        reg.exe add "HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v AppsUseLightTheme /t REG_DWORD /d 0 /f | Out-Null
        reg.exe add "HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v SystemUsesLightTheme /t REG_DWORD /d 0 /f | Out-Null
    }
    if ($config.Customization.ClassicContextMenu) {
        reg.exe add "HKLM\zNTUSER\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" /f /ve | Out-Null
    }
    if ($config.Customization.TaskbarAlignLeft) {
        reg.exe add "HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarAl /t REG_DWORD /d 0 /f | Out-Null
    }
    if ($config.Customization.ClassicStartMenuLayout) {
        reg.exe add "HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v Start_Layout /t REG_DWORD /d 1 /f | Out-Null
        reg.exe add "HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v Start_TrackProgs /t REG_DWORD /d 1 /f | Out-Null
        reg.exe add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\Explorer" /v ShowOrHideMostUsedApps /t REG_DWORD /d 1 /f | Out-Null
    }
    if ($config.Customization.ShowClassicDesktopIcons) {
        foreach ($deskKey in @(
            "HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel",
            "HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\ClassicStartMenu"
        )) {
            reg.exe add $deskKey /v "{20D04FE0-3AEA-1069-A2D8-08002B30309D}" /t REG_DWORD /d 0 /f | Out-Null
            reg.exe add $deskKey /v "{5399E694-6CE5-4D6C-8FCE-1D8870FDCBA0}" /t REG_DWORD /d 0 /f | Out-Null
        }
    }
    if ($config.Customization.ExplorerLaunchToThisPC) {
        reg.exe add "HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v LaunchTo /t REG_DWORD /d 1 /f | Out-Null
    }
    if ($config.Customization.DisableTransparencyAndAnimations) {
        reg.exe add "HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v EnableTransparency /t REG_DWORD /d 0 /f | Out-Null
        reg.exe add "HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarAnimations /t REG_DWORD /d 0 /f | Out-Null
        reg.exe add "HKLM\zNTUSER\Control Panel\Desktop\WindowMetrics" /v MinAnimate /t REG_SZ /d "0" /f | Out-Null
        reg.exe add "HKLM\zNTUSER\Control Panel\Desktop" /v MenuShowDelay /t REG_SZ /d "0" /f | Out-Null
    }
    if ($config.Customization.ShowFileExtensions) {
        reg.exe add "HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v HideFileExt /t REG_DWORD /d 0 /f | Out-Null
    }
    if ($config.Customization.HideTaskbarSearch) {
        reg.exe add "HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" /v SearchboxTaskbarMode /t REG_DWORD /d 0 /f | Out-Null
    }
    if ($config.Customization.HideTaskViewButton) {
        reg.exe add "HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowTaskViewButton /t REG_DWORD /d 0 /f | Out-Null
    }
    if ($config.Customization.HideWidgets) {
        # TaskbarDa is write-protected by UCPD.sys on Win11 24H2+ (Access is denied); the Dsh policy removes the Widgets button instead
        reg.exe add "HKLM\zSOFTWARE\Policies\Microsoft\Dsh" /v AllowNewsAndInterests /t REG_DWORD /d 0 /f | Out-Null
    }
    if ($config.Customization.HideChatIcon) {
        reg.exe add "HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarMn /t REG_DWORD /d 0 /f | Out-Null
    }
    if ($config.POSOptimizations -and $config.POSOptimizations.DisableReservedStorageAndHibernation) {
        reg.exe add "HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager" /v ShippedWithReserves /t REG_DWORD /d 0 /f 2>$null | Out-Null
        reg.exe add "HKLM\zSYSTEM\ControlSet001\Control\Power" /v HibernateEnabled /t REG_DWORD /d 0 /f 2>$null | Out-Null
        reg.exe add "HKLM\zSYSTEM\ControlSet001\Control\Power" /v HibernateEnabledDefault /t REG_DWORD /d 0 /f 2>$null | Out-Null
    }

    # 6f. Default User & System Screen Regional (en-CY), Currency (" ") & 24-Hour Time Settings
    foreach ($intlHive in @("HKLM\zNTUSER\Control Panel\International", "HKLM\zDEFAULT\Control Panel\International")) {
        if ($config.Regional.UserLocale) {
            reg.exe add $intlHive /v LocaleName /t REG_SZ /d "$($config.Regional.UserLocale)" /f 2>$null | Out-Null
            reg.exe add $intlHive /v Locale /t REG_SZ /d "00000C00" /f 2>$null | Out-Null
            reg.exe add $intlHive /v sShortDate /t REG_SZ /d "dd/MM/yyyy" /f 2>$null | Out-Null
            reg.exe add $intlHive /v iDate /t REG_SZ /d "1" /f 2>$null | Out-Null
            reg.exe add $intlHive /v iFirstDayOfWeek /t REG_SZ /d "0" /f 2>$null | Out-Null
            reg.exe add $intlHive /v iMeasure /t REG_SZ /d "0" /f 2>$null | Out-Null
            reg.exe add $intlHive /v iCountry /t REG_SZ /d "357" /f 2>$null | Out-Null
        }
        if ($null -ne $config.Regional.CurrencySymbol) {
            reg.exe add $intlHive /v sCurrency /t REG_SZ /d "$($config.Regional.CurrencySymbol)" /f 2>$null | Out-Null
        }
        if ($config.Regional.Use24HourTime) {
            reg.exe add $intlHive /v iTime /t REG_SZ /d "1" /f 2>$null | Out-Null
            reg.exe add $intlHive /v iTLZero /t REG_SZ /d "1" /f 2>$null | Out-Null
            reg.exe add $intlHive /v iTimePrefix /t REG_SZ /d "0" /f 2>$null | Out-Null
            reg.exe add $intlHive /v sShortTime /t REG_SZ /d "$($config.Regional.ShortTimeFormat)" /f 2>$null | Out-Null
            reg.exe add $intlHive /v sTimeFormat /t REG_SZ /d "$($config.Regional.LongTimeFormat)" /f 2>$null | Out-Null
        }
    }

    # Enforce strictly English (US) Keyboard Layout (00000409) in Default User
    reg.exe delete "HKLM\zNTUSER\Keyboard Layout\Preload" /f 2>$null | Out-Null
    reg.exe add "HKLM\zNTUSER\Keyboard Layout\Preload" /v "1" /t REG_SZ /d "00000409" /f | Out-Null
    reg.exe delete "HKLM\zNTUSER\Keyboard Layout\Substitutes" /f 2>$null | Out-Null
    reg.exe add "HKLM\zNTUSER\Keyboard Layout\Substitutes" /f | Out-Null

    # 6g. OOBE-Safe POS Registry Optimizations (Remaining POS tweaks run in FirstLogon.ps1 after OOBE finishes)
    if ($config.POSOptimizations) {
        if ($config.POSOptimizations.AllowBlankPasswordNetworkAccess) {
            reg.exe add "HKLM\zSYSTEM\ControlSet001\Control\Lsa" /v LimitBlankPasswordUse /t REG_DWORD /d 0 /f | Out-Null
        }
        if ($config.POSOptimizations.DisableLockScreen) {
            reg.exe add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\Personalization" /v NoLockScreen /t REG_DWORD /d 1 /f | Out-Null
            reg.exe add "HKLM\zNTUSER\Control Panel\Desktop" /v ScreenSaveActive /t REG_SZ /d "0" /f | Out-Null
        }
        if ($config.POSOptimizations.DisableWindowsUpdateAutoReboot) {
            reg.exe add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v NoAutoRebootWithLoggedOnUsers /t REG_DWORD /d 1 /f | Out-Null
            reg.exe add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v AUOptions /t REG_DWORD /d 3 /f | Out-Null
        }
        if ($config.POSOptimizations.DisableFinishSetupNagScreen) {
            reg.exe add "HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" /v ScoobeSystemSettingEnabled /t REG_DWORD /d 0 /f | Out-Null
        }
        if ($config.POSOptimizations.DisableUSBSelectiveSuspend) {
            # Per-hub power management (powercfg only covers the global scheme setting)
            reg.exe add "HKLM\zSYSTEM\ControlSet001\Services\USB" /v DisableSelectiveSuspend /t REG_DWORD /d 1 /f | Out-Null
        }
        if ($config.POSOptimizations.DisableReservedStorageAndHibernation) {
            reg.exe add "HKLM\zSYSTEM\ControlSet001\Control\Session Manager\Power" /v HiberbootEnabled /t REG_DWORD /d 0 /f | Out-Null
        }
        if ($config.POSOptimizations.LockDefaultPrinter) {
            reg.exe add "HKLM\zNTUSER\Software\Microsoft\Windows NT\CurrentVersion\Windows" /v LegacyDefaultPrinterMode /t REG_DWORD /d 1 /f | Out-Null
        }
        if ($config.POSOptimizations.EnableNetworkDeviceDiscoveryServices) {
            foreach ($svc in @("fdPHost", "FDResPub", "SSDPSRV", "upnphost")) {
                reg.exe add "HKLM\zSYSTEM\ControlSet001\Services\$svc" /v Start /t REG_DWORD /d 2 /f | Out-Null
            }
        }
        if ($config.POSOptimizations.DisableAutoPlay) {
            reg.exe add "HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v NoDriveTypeAutoRun /t REG_DWORD /d 255 /f | Out-Null
            reg.exe add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\Explorer" /v NoAutoplayfornonVolume /t REG_DWORD /d 1 /f | Out-Null
            reg.exe add "HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers" /v DisableAutoplay /t REG_DWORD /d 1 /f | Out-Null
        }
        if ($config.POSOptimizations.DisableDeliveryOptimization) {
            reg.exe add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" /v DODownloadMode /t REG_DWORD /d 0 /f | Out-Null
        }
        if ($config.POSOptimizations.DisableToastNotifications) {
            reg.exe add "HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\PushNotifications" /v ToastEnabled /t REG_DWORD /d 0 /f | Out-Null
            reg.exe add "HKLM\zNTUSER\Software\Policies\Microsoft\Windows\CurrentVersion\PushNotifications" /v NoToastApplicationNotification /t REG_DWORD /d 1 /f | Out-Null
        }
        if ($config.POSOptimizations.PinFeatureRelease) {
            $wuPol = "HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
            reg.exe add $wuPol /v TargetReleaseVersion /t REG_DWORD /d 1 /f | Out-Null
            reg.exe add $wuPol /v ProductVersion /t REG_SZ /d "Windows 11" /f | Out-Null
            reg.exe add $wuPol /v TargetReleaseVersionInfo /t REG_SZ /d "$($config.POSOptimizations.PinFeatureRelease)" /f | Out-Null
        }

        # 6h. Performance tuning for low-power POS hardware
        if ($config.POSOptimizations.BestPerformanceVisualEffects) {
            $vfxUser = "HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer"
            reg.exe add "$vfxUser\VisualEffects" /v VisualFXSetting /t REG_DWORD /d 3 /f | Out-Null
            # "Best performance" mask with font smoothing left on
            reg.exe add "HKLM\zNTUSER\Control Panel\Desktop" /v UserPreferencesMask /t REG_BINARY /d 9012038010000000 /f | Out-Null
            reg.exe add "HKLM\zNTUSER\Control Panel\Desktop" /v DragFullWindows /t REG_SZ /d "0" /f | Out-Null
            reg.exe add "HKLM\zNTUSER\Control Panel\Desktop" /v FontSmoothing /t REG_SZ /d "2" /f | Out-Null
            reg.exe add "$vfxUser\Advanced" /v IconsOnly /t REG_DWORD /d 1 /f | Out-Null
            reg.exe add "$vfxUser\Advanced" /v ListviewShadow /t REG_DWORD /d 0 /f | Out-Null
            reg.exe add "$vfxUser\Advanced" /v ListviewAlphaSelect /t REG_DWORD /d 0 /f | Out-Null
            reg.exe add "HKLM\zNTUSER\Software\Microsoft\Windows\DWM" /v EnableAeroPeek /t REG_DWORD /d 0 /f | Out-Null
            reg.exe add "HKLM\zNTUSER\Software\Microsoft\Windows\DWM" /v AlwaysHibernateThumbnails /t REG_DWORD /d 0 /f | Out-Null
        }
        if ($config.POSOptimizations.ForegroundPriorityBoost) {
            reg.exe add "HKLM\zSYSTEM\ControlSet001\Control\PriorityControl" /v Win32PrioritySeparation /t REG_DWORD /d 0x26 /f | Out-Null
        }
        # NtfsOptimizations, PageFile, Ndu/NetworkThrottling: applied post-OOBE in SetupComplete.ps1 (see 6c-2 note)
        if ($config.POSOptimizations.DefenderLowImpact) {
            $defScan = "HKLM\zSOFTWARE\Policies\Microsoft\Windows Defender\Scan"
            reg.exe add $defScan /v AvgCPULoadFactor /t REG_DWORD /d 20 /f | Out-Null
            reg.exe add $defScan /v ScanOnlyIfIdle /t REG_DWORD /d 1 /f | Out-Null
            reg.exe add $defScan /v DisableCatchupFullScan /t REG_DWORD /d 1 /f | Out-Null
            reg.exe add $defScan /v DisableCatchupQuickScan /t REG_DWORD /d 1 /f | Out-Null
            reg.exe add $defScan /v ScheduleDay /t REG_DWORD /d 8 /f | Out-Null
            foreach ($exPath in @($config.POSOptimizations.DefenderExclusionPaths)) {
                if ($exPath) {
                    reg.exe add "HKLM\zSOFTWARE\Policies\Microsoft\Windows Defender\Exclusions" /v Exclusions_Paths /t REG_DWORD /d 1 /f | Out-Null
                    reg.exe add "HKLM\zSOFTWARE\Policies\Microsoft\Windows Defender\Exclusions\Paths" /v "$exPath" /t REG_SZ /d 0 /f | Out-Null
                }
            }
        }
        if ($config.POSOptimizations.DisableAutomaticMaintenance) {
            reg.exe add "HKLM\zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\Maintenance" /v MaintenanceDisabled /t REG_DWORD /d 1 /f | Out-Null
        }
        if ($config.POSOptimizations.FastBootTweaks) {
            reg.exe add "HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize" /v StartupDelayInMSec /t REG_DWORD /d 0 /f | Out-Null
        }
        if ($config.POSOptimizations.DisableClipboardHistoryAndGameMode) {
            reg.exe add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\System" /v AllowClipboardHistory /t REG_DWORD /d 0 /f | Out-Null
            reg.exe add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\System" /v AllowCrossDeviceClipboard /t REG_DWORD /d 0 /f | Out-Null
            reg.exe add "HKLM\zNTUSER\Software\Microsoft\Clipboard" /v EnableClipboardHistory /t REG_DWORD /d 0 /f | Out-Null
            reg.exe add "HKLM\zNTUSER\Software\Microsoft\GameBar" /v AutoGameModeEnabled /t REG_DWORD /d 0 /f | Out-Null
            reg.exe add "HKLM\zNTUSER\Software\Microsoft\GameBar" /v AllowAutoGameMode /t REG_DWORD /d 0 /f | Out-Null
            reg.exe add "HKLM\zNTUSER\Software\Microsoft\GameBar" /v UseNexusForGameBarEnabled /t REG_DWORD /d 0 /f | Out-Null
            reg.exe add "HKLM\zNTUSER\System\GameConfigStore" /v GameDVR_Enabled /t REG_DWORD /d 0 /f | Out-Null
        }
    }
} finally {
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
    Start-Sleep -Seconds 2
    foreach ($hive in @("zCOMPONENTS", "zDEFAULT", "zNTUSER", "zSOFTWARE", "zSYSTEM")) {
        reg.exe unload "HKLM\$hive" 2>$null | Out-Null
    }
}
} # End if (-not $QuickUpdateScripts) for Steps 2-6

# ---------------------------------------------------------------------------
# 7. Stage $OEM$ Provisioning Scripts & Pre-Installed Applications
# ---------------------------------------------------------------------------
Write-Host "`n[7/9] Staging `$OEM`$ Provisioning Scripts & Pre-Installed Applications..." -ForegroundColor Yellow

$oemSystemDrive = Join-Path $IsoStageDir "sources\`$OEM`$\`$1\TinyWin"
$oemScriptsDir  = Join-Path $oemSystemDrive "Scripts"
$oemInstallDir  = Join-Path $oemSystemDrive "Apps\Installers"
$oemCacheDir    = Join-Path $oemSystemDrive "Apps\WingetCache"
$oemWinSetupDir = Join-Path $IsoStageDir "sources\`$OEM`$\`$`$\Setup\Scripts"

foreach ($d in @($oemScriptsDir, $oemInstallDir, $oemCacheDir, $oemWinSetupDir)) {
    New-Item -ItemType Directory -Path $d -Force | Out-Null
}

# Copy config.json and scripts
Copy-Item -Path $ConfigPath -Destination (Join-Path $oemSystemDrive "config.json") -Force
Copy-Item -Path (Join-Path $PSScriptRoot "scripts\FirstLogon.ps1") -Destination (Join-Path $oemScriptsDir "FirstLogon.ps1") -Force
Copy-Item -Path (Join-Path $PSScriptRoot "scripts\SetupComplete.ps1") -Destination (Join-Path $oemScriptsDir "SetupComplete.ps1") -Force
Copy-Item -Path (Join-Path $PSScriptRoot "scripts\SetupComplete.cmd") -Destination (Join-Path $oemWinSetupDir "SetupComplete.cmd") -Force

# Copy any offline installers from apps\installers\ (e.g. meshagent.exe)
$localInstallersDir = Join-Path $PSScriptRoot "apps\installers"
if (Test-Path $localInstallersDir) {
    $installerFiles = Get-ChildItem -Path $localInstallersDir -File | Where-Object { $_.Name -ne "README.md" -and $_.Name -ne ".gitkeep" }
    foreach ($f in $installerFiles) {
        Write-Host "    [+] Bundling offline installer: $($f.Name)" -ForegroundColor Green
        Copy-Item -Path $f.FullName -Destination (Join-Path $oemInstallDir $f.Name) -Force
    }
}

# Optional: Pre-download Winget applications into persistent local cache (apps\cache) & copy into ISO
if ($PreDownloadApps -or $config.Applications.PreDownloadWingetOnBuild) {
    Write-Host "    [*] Caching VC++ Redistributables, LibreWolf, and TeamViewer into ISO..." -ForegroundColor Cyan
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $persistentCacheRoot = Join-Path $PSScriptRoot "apps\cache"
    New-Item -ItemType Directory -Path $persistentCacheRoot -Force | Out-Null

    foreach ($pkg in $config.Applications.WingetPackages) {
        if (-not $pkg.Enabled) { continue }
        $pkgDir = Join-Path $oemCacheDir $pkg.Id
        $localPkgCache = Join-Path $persistentCacheRoot $pkg.Id
        New-Item -ItemType Directory -Path $pkgDir -Force | Out-Null
        New-Item -ItemType Directory -Path $localPkgCache -Force | Out-Null

        $existingCached = Get-ChildItem -Path $localPkgCache -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($existingCached) {
            Copy-Item -Path $existingCached.FullName -Destination (Join-Path $pkgDir $existingCached.Name) -Force
            Write-Host "        [+] Reused local cached installer: $($existingCached.Name)" -ForegroundColor Green
            continue
        }

        try {
            switch ($pkg.Id) {
                "Microsoft.VCRedist.2015+.x64" {
                    $destFile = Join-Path $localPkgCache "vc_redist.x64.exe"
                    Invoke-WebRequest -Uri "https://aka.ms/vs/17/release/vc_redist.x64.exe" -OutFile $destFile -UseBasicParsing
                    Copy-Item -Path $destFile -Destination (Join-Path $pkgDir "vc_redist.x64.exe") -Force
                    Write-Host "        [+] Downloaded & cached VC++ Redistributable x64" -ForegroundColor Green
                }
                "Microsoft.VCRedist.2015+.x86" {
                    $destFile = Join-Path $localPkgCache "vc_redist.x86.exe"
                    Invoke-WebRequest -Uri "https://aka.ms/vs/17/release/vc_redist.x86.exe" -OutFile $destFile -UseBasicParsing
                    Copy-Item -Path $destFile -Destination (Join-Path $pkgDir "vc_redist.x86.exe") -Force
                    Write-Host "        [+] Downloaded & cached VC++ Redistributable x86" -ForegroundColor Green
                }
                "TeamViewer.TeamViewer" {
                    $destFile = Join-Path $localPkgCache "TeamViewer_Setup_x64.exe"
                    Invoke-WebRequest -Uri "https://download.teamviewer.com/download/TeamViewer_Setup_x64.exe" -OutFile $destFile -UseBasicParsing
                    Copy-Item -Path $destFile -Destination (Join-Path $pkgDir "TeamViewer_Setup_x64.exe") -Force
                    Write-Host "        [+] Downloaded & cached TeamViewer x64" -ForegroundColor Green
                }
                "LibreWolf.LibreWolf" {
                    $cached = $false
                    try {
                        $release = Invoke-RestMethod -Uri "https://codeberg.org/api/v1/repos/librewolf/bsys6/releases/latest" -Headers @{ "User-Agent" = "TinyWin11Builder" }
                        $asset = $release.assets | Where-Object { $_.name -match "windows-x86_64-setup\.exe$" } | Select-Object -First 1
                        if ($asset) {
                            $destFile = Join-Path $localPkgCache $asset.name
                            Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $destFile -UseBasicParsing
                            Copy-Item -Path $destFile -Destination (Join-Path $pkgDir $asset.name) -Force
                            Write-Host "        [+] Downloaded & cached LibreWolf ($($asset.name)) from Codeberg" -ForegroundColor Green
                            $cached = $true
                        }
                    } catch {}
                    if (-not $cached) {
                        $glReleases = Invoke-RestMethod -Uri "https://gitlab.com/api/v4/projects/44042130/releases" -Headers @{ "User-Agent" = "TinyWin11Builder" }
                        $glLink = $glReleases[0].assets.links | Where-Object { $_.name -match "windows-x86_64-setup\.exe$" } | Select-Object -First 1
                        if ($glLink) {
                            $destFile = Join-Path $localPkgCache $glLink.name
                            Invoke-WebRequest -Uri $glLink.direct_asset_url -OutFile $destFile -UseBasicParsing
                            Copy-Item -Path $destFile -Destination (Join-Path $pkgDir $glLink.name) -Force
                            Write-Host "        [+] Downloaded & cached LibreWolf ($($glLink.name)) from GitLab" -ForegroundColor Green
                        }
                    }
                }
                default {
                    winget.exe download --id $pkg.Id --exact --download-directory $localPkgCache --accept-package-agreements --accept-source-agreements 2>$null | Out-Null
                    Get-ChildItem -Path $localPkgCache -File -ErrorAction SilentlyContinue | Copy-Item -Destination $pkgDir -Force
                }
            }
        } catch {
            Write-Warning "        Could not pre-download $($pkg.Id): $_ (will install online at FirstLogon)"
        }
    }
}

# Generate autounattend.xml in ISO root
& (Join-Path $PSScriptRoot "scripts\Generate-Autounattend.ps1") -ConfigPath $ConfigPath -OutputPath (Join-Path $IsoStageDir "autounattend.xml")

# ---------------------------------------------------------------------------
# 8. Cleanup WinSxS, Unmount install.wim, Patch boot.wim & Compress
# ---------------------------------------------------------------------------
if (-not $QuickUpdateScripts) {
Write-Host "`n[8/9] Cleaning Up Component Store & Committing Image..." -ForegroundColor Yellow

if ($config.Compression.CleanupWinSxS) {
    if ($config.POSOptimizations -and $config.POSOptimizations.EnableDotNet35) {
        Write-Host "    [i] Skipping offline WinSxS component cleanup to preserve pending .NET 3.5 (NetFx3) servicing transaction..." -ForegroundColor Gray
    } else {
        Write-Host "    [*] Running DISM StartComponentCleanup /ResetBase..." -ForegroundColor Cyan
        dism.exe /Image:"$MountDir" /Cleanup-Image /StartComponentCleanup /ResetBase
    }
}

Write-Host "    [*] Unmounting and saving install.wim..." -ForegroundColor Cyan
dism.exe /Unmount-Image /MountDir:"$MountDir" /Commit
if ($LASTEXITCODE -ne 0) { throw "Failed to unmount install.wim." }

# Set custom OS Name & Description inside WIM metadata
Set-WimImageMetadata -WimPath $wimPath -ImageIndex 1 -NewName $config.Branding.OSName -NewDescription $config.Branding.OSDescription

# Export to ESD only if explicitly requested; keeping WIM directly saves 12-15 minutes of LZMS compression
if ($config.Compression.ExportFormat -eq "esd") {
    Write-Host "    [*] Compressing install.wim to install.esd (recovery compression for minimum ISO size)..." -ForegroundColor Cyan
    dism.exe /Export-Image /SourceImageFile:"$wimPath" /SourceIndex:1 /DestinationImageFile:"$esdPath" /Compress:recovery /CheckIntegrity
    if ($LASTEXITCODE -eq 0) {
        Remove-Item -Path $wimPath -Force
        Set-WimImageMetadata -WimPath $esdPath -ImageIndex 1 -NewName $config.Branding.OSName -NewDescription $config.Branding.OSDescription
    }
} else {
    Write-Host "    [+] Keeping fast-compressed install.wim directly (skipping slow re-compression)." -ForegroundColor Green
}

# Patch boot.wim (Index 2 - Windows Setup) with hardware check bypasses & VirtIO boot drivers
$bootWimPath = Join-Path $IsoStageDir "sources\boot.wim"
Write-Host "    [*] Patching sources\boot.wim (Index 2) with hardware check bypasses & VirtIO Setup drivers..." -ForegroundColor Cyan
dism.exe /Mount-Image /ImageFile:"$bootWimPath" /Index:2 /MountDir:"$BootMount"
if ($LASTEXITCODE -eq 0) {
    if ($config.Drivers -and $config.Drivers.InjectVirtIOBootDriversIntoBootWim) {
        $virtioRoot = if ($config.Drivers.VirtIOFolder) { Join-Path $PSScriptRoot $config.Drivers.VirtIOFolder } else { Join-Path $PSScriptRoot "drivers\VirtIO" }
        foreach ($bootDrvRel in @("viostor", "vioscsi", "NetKVM", "vioinput")) {
            $bootDrvPath = Join-Path $virtioRoot $bootDrvRel
            if (Test-Path $bootDrvPath) {
                Write-Host "        [+] Injecting VirtIO WinPE driver into boot.wim: $bootDrvRel" -ForegroundColor Gray
                dism.exe /Image:"$BootMount" /Add-Driver /Driver:"$bootDrvPath" /Recurse | Out-Null
            }
        }
    }

    reg.exe load HKLM\zBOOTSYSTEM "$BootMount\Windows\System32\config\SYSTEM" | Out-Null
    try {
        reg.exe add "HKLM\zBOOTSYSTEM\Setup\LabConfig" /v BypassTPMCheck /t REG_DWORD /d 1 /f | Out-Null
        reg.exe add "HKLM\zBOOTSYSTEM\Setup\LabConfig" /v BypassSecureBootCheck /t REG_DWORD /d 1 /f | Out-Null
        reg.exe add "HKLM\zBOOTSYSTEM\Setup\LabConfig" /v BypassRAMCheck /t REG_DWORD /d 1 /f | Out-Null
        reg.exe add "HKLM\zBOOTSYSTEM\Setup\LabConfig" /v BypassCPUCheck /t REG_DWORD /d 1 /f | Out-Null
        reg.exe add "HKLM\zBOOTSYSTEM\Setup\LabConfig" /v BypassStorageCheck /t REG_DWORD /d 1 /f | Out-Null
    } finally {
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
        Start-Sleep -Seconds 1
        reg.exe unload HKLM\zBOOTSYSTEM 2>$null | Out-Null
    }
    dism.exe /Unmount-Image /MountDir:"$BootMount" /Commit
}
} # End if (-not $QuickUpdateScripts) for Step 8

# ---------------------------------------------------------------------------
# 9. Build Bootable ISO via oscdimg.exe
# ---------------------------------------------------------------------------
Write-Host "`n[9/9] Building Bootable UEFI + Legacy BIOS ISO..." -ForegroundColor Yellow

$oscdimgPath = Join-Path $PSScriptRoot "tools\oscdimg.exe"
$adkPaths = @(
    "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
    "${env:ProgramFiles}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
)
foreach ($p in $adkPaths) {
    if (Test-Path $p) { $oscdimgPath = $p; break }
}

if (-not (Test-Path $oscdimgPath)) {
    $toolsDir = Join-Path $PSScriptRoot "tools"
    New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null
    $oscdimgPath = Join-Path $toolsDir "oscdimg.exe"
    Write-Host "    [*] Downloading oscdimg.exe to $oscdimgPath..." -ForegroundColor Cyan
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri "https://msdl.microsoft.com/download/symbols/oscdimg.exe/3D44737265000/oscdimg.exe" -OutFile $oscdimgPath -UseBasicParsing
}

$OutputIsoPath = [System.IO.Path]::GetFullPath($OutputIsoPath)
$outputDir = Split-Path -Path $OutputIsoPath -Parent
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

# Run oscdimg from inside $IsoStageDir using relative boot sector paths so embedded quotes are never needed
Push-Location $IsoStageDir
try {
    $bootData = "2#p0,e,bboot\etfsboot.com#pEF,e,befi\microsoft\boot\efisys.bin"
    & $oscdimgPath -m -o -u2 -udfver102 "-bootdata:$bootData" -l"POS_READY_2026" "." "$OutputIsoPath"
    if ($LASTEXITCODE -ne 0) {
        throw "oscdimg.exe failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

# Clean up temporary working directory after successful ISO creation
if (Test-Path $WorkDir) {
    Write-Host "    [*] Cleaning temporary working directory ($WorkDir)..." -ForegroundColor Gray
    Remove-Item -Path $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n==================================================================" -ForegroundColor Green
Write-Host "   [+] SUCCESS! Custom TinyWin 11 ISO Created:" -ForegroundColor Green
Write-Host "       $OutputIsoPath" -ForegroundColor White
Write-Host "==================================================================" -ForegroundColor Green
Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
