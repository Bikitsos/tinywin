<#
.SYNOPSIS
    Runs at first user logon (via autounattend.xml FirstLogonCommands).
    Applies desktop/wallpaper tweaks and installs offline & Winget applications
    (VC++ Redistributables, LibreWolf, TeamViewer, MeshCentral, etc.).
#>
$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

$TinyWinRoot = "C:\TinyWin"
$LogDir      = Join-Path $TinyWinRoot "Logs"
$ConfigPath  = Join-Path $TinyWinRoot "config.json"
$InstallDir  = Join-Path $TinyWinRoot "Apps\Installers"
$CacheDir    = Join-Path $TinyWinRoot "Apps\WingetCache"

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

Start-Transcript -Path (Join-Path $LogDir "FirstLogon.log") -Append

$Host.UI.RawUI.WindowTitle = "TinyWin 11 - Post-Install Provisioning"
Write-Host "=============================================================" -ForegroundColor Cyan
Write-Host "   TinyWin 11 - First Logon Customization & App Installer    " -ForegroundColor Cyan
Write-Host "=============================================================" -ForegroundColor Cyan

if (-not (Test-Path $ConfigPath)) {
    Write-Warning "Configuration file not found at $ConfigPath. Exiting."
    Stop-Transcript
    exit 0
}

$config = Get-Content -Path $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json

# ---------------------------------------------------------------------------
# 1. Apply User UI, Regional & Wallpaper Customizations
# ---------------------------------------------------------------------------
Write-Host "`n[1/4] Applying User Interface & Regional Customizations..." -ForegroundColor Yellow

# Classic Windows 10 right-click context menu
if ($config.Customization.ClassicContextMenu) {
    reg.exe add "HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" /f /ve | Out-Null
}

# Dark Mode
if ($config.Customization.DarkModeDefault) {
    reg.exe add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v AppsUseLightTheme /t REG_DWORD /d 0 /f | Out-Null
    reg.exe add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v SystemUsesLightTheme /t REG_DWORD /d 0 /f | Out-Null
}

# Explorer File Extensions & Hidden Files
if ($config.Customization.ShowFileExtensions) {
    reg.exe add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v HideFileExt /t REG_DWORD /d 0 /f | Out-Null
}
if ($config.Customization.ShowHiddenFiles) {
    reg.exe add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v Hidden /t REG_DWORD /d 1 /f | Out-Null
}

# Taskbar & Classic Windows 7 UI Customizations
if ($config.Customization.TaskbarAlignLeft) {
    reg.exe add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarAl /t REG_DWORD /d 0 /f | Out-Null
}
if ($config.Customization.ClassicStartMenuLayout) {
    reg.exe add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v Start_Layout /t REG_DWORD /d 1 /f | Out-Null
    reg.exe add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v Start_TrackProgs /t REG_DWORD /d 1 /f | Out-Null
    reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Explorer" /v ShowOrHideMostUsedApps /t REG_DWORD /d 1 /f | Out-Null
}
if ($config.Customization.ShowClassicDesktopIcons) {
    foreach ($deskKey in @(
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\ClassicStartMenu"
    )) {
        reg.exe add $deskKey /v "{20D04FE0-3AEA-1069-A2D8-08002B30309D}" /t REG_DWORD /d 0 /f | Out-Null
        reg.exe add $deskKey /v "{5399E694-6CE5-4D6C-8FCE-1D8870FDCBA0}" /t REG_DWORD /d 0 /f | Out-Null
    }
}
if ($config.Customization.ExplorerLaunchToThisPC) {
    reg.exe add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v LaunchTo /t REG_DWORD /d 1 /f | Out-Null
}
if ($config.Customization.DisableTransparencyAndAnimations) {
    reg.exe add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v EnableTransparency /t REG_DWORD /d 0 /f | Out-Null
    reg.exe add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarAnimations /t REG_DWORD /d 0 /f | Out-Null
    reg.exe add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ListviewAlphaSelect /t REG_DWORD /d 0 /f | Out-Null
    reg.exe add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ListviewShadow /t REG_DWORD /d 0 /f | Out-Null
    reg.exe add "HKCU\Control Panel\Desktop\WindowMetrics" /v MinAnimate /t REG_SZ /d "0" /f | Out-Null
    reg.exe add "HKCU\Control Panel\Desktop" /v MenuShowDelay /t REG_SZ /d "0" /f | Out-Null
    reg.exe add "HKCU\Control Panel\Desktop" /v FontSmoothing /t REG_SZ /d "2" /f | Out-Null
    reg.exe add "HKCU\Control Panel\Desktop" /v FontSmoothingType /t REG_DWORD /d 2 /f | Out-Null
}
if ($config.Customization.HideTaskbarSearch) {
    reg.exe add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" /v SearchboxTaskbarMode /t REG_DWORD /d 0 /f | Out-Null
}
if ($config.Customization.HideTaskViewButton) {
    reg.exe add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowTaskViewButton /t REG_DWORD /d 0 /f | Out-Null
}
if ($config.Customization.HideWidgets) {
    # TaskbarDa is write-protected by UCPD.sys on Win11 24H2+; use the Dsh policy instead
    reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Dsh" /v AllowNewsAndInterests /t REG_DWORD /d 0 /f | Out-Null
}
if ($config.Customization.HideChatIcon) {
    reg.exe add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarMn /t REG_DWORD /d 0 /f | Out-Null
}

# POS Tweaks (Screensaver, Nag Screen, StickyKeys, Touchscreen, Shared Printers/SMB, NIC Power, Firewall, UAC, NTP, Reserved Storage)
if ($config.POSOptimizations) {
    if ($config.POSOptimizations.DisableLockScreen) {
        reg.exe add "HKCU\Control Panel\Desktop" /v ScreenSaveActive /t REG_SZ /d "0" /f | Out-Null
    }
    if ($config.POSOptimizations.DisableFinishSetupNagScreen) {
        reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" /v ScoobeSystemSettingEnabled /t REG_DWORD /d 0 /f | Out-Null
    }
    if ($config.POSOptimizations.DisableStickyAndFilterKeysPopups) {
        reg.exe add "HKCU\Control Panel\Accessibility\StickyKeys" /v Flags /t REG_SZ /d "506" /f | Out-Null
        reg.exe add "HKCU\Control Panel\Accessibility\ToggleKeys" /v Flags /t REG_SZ /d "58" /f | Out-Null
        reg.exe add "HKCU\Control Panel\Accessibility\Keyboard Response" /v Flags /t REG_SZ /d "122" /f | Out-Null
    }
    if ($config.POSOptimizations.TouchscreenDisableEdgeSwipeAndAutoKeyboard) {
        reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\EdgeUI" /v AllowEdgeSwipe /t REG_DWORD /d 0 /f | Out-Null
        reg.exe add "HKCU\Software\Microsoft\TabletTip\1.7" /v EnableDesktopModeAutoInvoke /t REG_DWORD /d 1 /f | Out-Null
        reg.exe add "HKCU\Software\Microsoft\TabletTip\1.7" /v TouchKeyboardTapInvoke /t REG_DWORD /d 2 /f | Out-Null
        reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI" /v ShowTabletKeyboard /t REG_DWORD /d 1 /f | Out-Null
    }
    if ($config.POSOptimizations.DisableNICAndPCIePowerSaving) {
        powercfg.exe /SETACVALUEINDEX SCHEME_CURRENT 501a4d13-42af-4429-9fd1-a8218c268e20 ee12f906-d277-404b-b6da-e5fa1a576df5 0 2>$null | Out-Null
        powercfg.exe /SETDCVALUEINDEX SCHEME_CURRENT 501a4d13-42af-4429-9fd1-a8218c268e20 ee12f906-d277-404b-b6da-e5fa1a576df5 0 2>$null | Out-Null
        powercfg.exe /SETACVALUEINDEX SCHEME_CURRENT 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 12bbebe6-58d6-4636-95bb-3217ef867c1a 0 2>$null | Out-Null
        powercfg.exe /SETDCVALUEINDEX SCHEME_CURRENT 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 12bbebe6-58d6-4636-95bb-3217ef867c1a 0 2>$null | Out-Null
        powercfg.exe /SETACTIVE SCHEME_CURRENT 2>$null | Out-Null
        Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Disable-NetAdapterPowerManagement -NoRestart -ErrorAction SilentlyContinue
    }
    if ($config.POSOptimizations.FixNetworkPrinterAndSMB24H2) {
        reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Print" /v RpcAuthnLevelPrivacyEnabled /t REG_DWORD /d 0 /f | Out-Null
        reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint" /v RestrictDriverInstallationToAdministrators /t REG_DWORD /d 0 /f | Out-Null
        reg.exe add "HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" /v AllowInsecureGuestAuth /t REG_DWORD /d 1 /f | Out-Null
        reg.exe add "HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" /v RequireSecuritySignature /t REG_DWORD /d 0 /f | Out-Null
        reg.exe add "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" /v RequireSecuritySignature /t REG_DWORD /d 0 /f | Out-Null
        reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\LanmanWorkstation" /v AllowInsecureGuestAuth /t REG_DWORD /d 1 /f | Out-Null
    }
    if ($config.POSOptimizations.SetPrivateNetworkAndEnableSharingAndPing) {
        Get-NetConnectionProfile -ErrorAction SilentlyContinue | Where-Object { $_.NetworkCategory -ne "DomainAuthenticated" } | ForEach-Object {
            Set-NetConnectionProfile -InterfaceIndex $_.InterfaceIndex -NetworkCategory Private -ErrorAction SilentlyContinue
        }
        netsh.exe advfirewall firewall set rule group="File and Printer Sharing" new enable=Yes 2>$null | Out-Null
        netsh.exe advfirewall firewall set rule group="Network Discovery" new enable=Yes 2>$null | Out-Null
        netsh.exe advfirewall firewall add rule name="POS Allow ICMPv4 Ping" protocol=icmpv4:8,any dir=in action=allow profile=private,domain 2>$null | Out-Null
    }
    if ($config.POSOptimizations.DisableUACSecureDesktopForRemoteSupport) {
        reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v PromptOnSecureDesktop /t REG_DWORD /d 0 /f | Out-Null
    }
    if ($config.POSOptimizations.AlwaysOnTimeSyncNTP) {
        if (Get-Service -Name "W32Time" -ErrorAction SilentlyContinue) {
            Set-Service -Name "W32Time" -StartupType Automatic -ErrorAction SilentlyContinue
            Start-Service -Name "W32Time" -ErrorAction SilentlyContinue
            w32tm.exe /resync /force 2>$null | Out-Null
        }
    }
    if ($config.POSOptimizations.DisableReservedStorageAndHibernation) {
        powercfg.exe /hibernate off 2>$null | Out-Null
        reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager" /v ShippedWithReserves /t REG_DWORD /d 0 /f 2>$null | Out-Null
    }
    if ($config.POSOptimizations.DisableErrorReportingPopups) {
        reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting" /v Disabled /t REG_DWORD /d 1 /f 2>$null | Out-Null
        reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting" /v DontShowUI /t REG_DWORD /d 1 /f 2>$null | Out-Null
        reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting" /v Disabled /t REG_DWORD /d 1 /f 2>$null | Out-Null
        reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting" /v DontShowUI /t REG_DWORD /d 1 /f 2>$null | Out-Null
    }
    if ($config.POSOptimizations.LockDefaultPrinter) {
        # Stop Windows switching the default printer to the last-used one (receipts going to the wrong printer)
        reg.exe add "HKCU\Software\Microsoft\Windows NT\CurrentVersion\Windows" /v LegacyDefaultPrinterMode /t REG_DWORD /d 1 /f | Out-Null
    }
    if ($config.POSOptimizations.DisableAutoPlay) {
        reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers" /v DisableAutoplay /t REG_DWORD /d 1 /f | Out-Null
    }
    if ($config.POSOptimizations.DisableToastNotifications) {
        reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\PushNotifications" /v ToastEnabled /t REG_DWORD /d 0 /f | Out-Null
        reg.exe add "HKCU\Software\Policies\Microsoft\Windows\CurrentVersion\PushNotifications" /v NoToastApplicationNotification /t REG_DWORD /d 1 /f | Out-Null
    }
    if ($config.POSOptimizations.BestPerformanceVisualEffects) {
        reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" /v VisualFXSetting /t REG_DWORD /d 3 /f | Out-Null
        reg.exe add "HKCU\Control Panel\Desktop" /v UserPreferencesMask /t REG_BINARY /d 9012038010000000 /f | Out-Null
        reg.exe add "HKCU\Control Panel\Desktop" /v DragFullWindows /t REG_SZ /d "0" /f | Out-Null
        reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v IconsOnly /t REG_DWORD /d 1 /f | Out-Null
        reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ListviewShadow /t REG_DWORD /d 0 /f | Out-Null
        reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ListviewAlphaSelect /t REG_DWORD /d 0 /f | Out-Null
        reg.exe add "HKCU\Software\Microsoft\Windows\DWM" /v EnableAeroPeek /t REG_DWORD /d 0 /f | Out-Null
        reg.exe add "HKCU\Software\Microsoft\Windows\DWM" /v AlwaysHibernateThumbnails /t REG_DWORD /d 0 /f | Out-Null
    }
    if ($config.POSOptimizations.FastBootTweaks) {
        reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize" /v StartupDelayInMSec /t REG_DWORD /d 0 /f | Out-Null
    }
    if ($config.POSOptimizations.DisableClipboardHistoryAndGameMode) {
        reg.exe add "HKCU\Software\Microsoft\Clipboard" /v EnableClipboardHistory /t REG_DWORD /d 0 /f | Out-Null
        reg.exe add "HKCU\Software\Microsoft\GameBar" /v AutoGameModeEnabled /t REG_DWORD /d 0 /f | Out-Null
        reg.exe add "HKCU\Software\Microsoft\GameBar" /v AllowAutoGameMode /t REG_DWORD /d 0 /f | Out-Null
        reg.exe add "HKCU\Software\Microsoft\GameBar" /v UseNexusForGameBarEnabled /t REG_DWORD /d 0 /f | Out-Null
        reg.exe add "HKCU\System\GameConfigStore" /v GameDVR_Enabled /t REG_DWORD /d 0 /f | Out-Null
    }

    # Post-OOBE machine-level performance tuning (kept out of SetupComplete, which runs before the OOBE UI)
    if ($config.POSOptimizations.DisableUSBSelectiveSuspend) {
        reg.exe add "HKLM\SYSTEM\CurrentControlSet\Services\usbhub\HubG" /v DisableOnSoftRemove /t REG_DWORD /d 1 /f 2>$null | Out-Null
    }
    if ($config.POSOptimizations.NtfsOptimizations) {
        fsutil.exe behavior set disablelastaccess 1 2>$null | Out-Null
        fsutil.exe behavior set disable8dot3 1 2>$null | Out-Null
    }
    if ($config.POSOptimizations.DefenderLowImpact) {
        Write-Host "    [*] Tuning Defender for low CPU impact (realtime protection stays on)..." -ForegroundColor Cyan
        try {
            Set-MpPreference -ScanAvgCPULoadFactor 20 -ScanOnlyIfIdleEnabled $true -DisableCatchupFullScan $true -DisableCatchupQuickScan $true -ScanScheduleDay 8 -ErrorAction Stop
            foreach ($exPath in @($config.POSOptimizations.DefenderExclusionPaths)) {
                if ($exPath) { Add-MpPreference -ExclusionPath $exPath -ErrorAction SilentlyContinue }
            }
        } catch { Write-Warning "        Defender tuning skipped: $_" }
    }
    if ($config.POSOptimizations.DisableAutomaticMaintenance) {
        reg.exe add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\Maintenance" /v MaintenanceDisabled /t REG_DWORD /d 1 /f | Out-Null
    }
    if ($config.POSOptimizations.DisableNonEssentialScheduledTasks) {
        Write-Host "    [*] Disabling non-essential scheduled tasks..." -ForegroundColor Cyan
        $posTasksToDisable = @(
            "\Microsoft\Windows\Defrag\ScheduledDefrag",
            "\Microsoft\Windows\Windows Error Reporting\QueueReporting",
            "\Microsoft\Windows\Feedback\Siuf\DmClient",
            "\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload",
            "\Microsoft\Windows\Maps\MapsUpdateTask",
            "\Microsoft\Windows\Maps\MapsToastTask",
            "\Microsoft\Windows\Device Information\Device",
            "\Microsoft\Windows\Device Information\Device User",
            "\Microsoft\Windows\Flighting\FeatureConfig\ReconcileFeatures",
            "\Microsoft\Windows\Flighting\OneSettings\RefreshCache",
            "\Microsoft\Windows\Shell\FamilySafetyMonitor",
            "\Microsoft\Windows\Shell\FamilySafetyRefreshTask",
            "\Microsoft\Windows\DiskFootprint\StorageSense",
            "\Microsoft\Windows\DiskFootprint\Diagnostics",
            "\Microsoft\Windows\Application Experience\StartupAppTask",
            "\Microsoft\Windows\Application Experience\PcaPatchDbTask",
            "\Microsoft\Windows\Application Experience\MareBackup",
            "\Microsoft\Windows\Application Experience\SdbinstMergeDbTask",
            "\Microsoft\Windows\Windows Defender\Windows Defender Scheduled Scan",
            "\Microsoft\Windows\Windows Defender\Windows Defender Cache Maintenance",
            "\Microsoft\Windows\Windows Defender\Windows Defender Cleanup",
            "\Microsoft\Windows\Windows Defender\Windows Defender Verification",
            "\Microsoft\Windows\Speech\SpeechModelDownloadTask",
            "\Microsoft\Windows\Printing\EduPrintProv",
            "\Microsoft\Windows\Work Folders\Work Folders Logon Synchronization",
            "\Microsoft\Windows\Work Folders\Work Folders Maintenance Work",
            "\Microsoft\Windows\WwanSvc\NotificationTask",
            "\Microsoft\XblGameSave\XblGameSaveTask"
        )
        foreach ($task in $posTasksToDisable) {
            schtasks.exe /Change /TN "$task" /Disable 2>$null | Out-Null
        }
    }
    if ($config.POSOptimizations.PageFileInitialMB -and $config.POSOptimizations.PageFileMaximumMB) {
        # "?:" = boot volume, independent of the drive letter Setup assigned
        reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" /v PagingFiles /t REG_MULTI_SZ /d "?:\pagefile.sys $($config.POSOptimizations.PageFileInitialMB) $($config.POSOptimizations.PageFileMaximumMB)" /f | Out-Null
    }
    if ($config.POSOptimizations.NetworkLatencyOptimizations) {
        reg.exe add "HKLM\SYSTEM\CurrentControlSet\Services\Ndu" /v Start /t REG_DWORD /d 4 /f 2>$null | Out-Null
        reg.exe add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v NetworkThrottlingIndex /t REG_DWORD /d 0xFFFFFFFF /f | Out-Null
        reg.exe add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v SystemResponsiveness /t REG_DWORD /d 0 /f | Out-Null
        # Nagle off per interface: lower latency for receipt printer / payment terminal sockets
        Get-ChildItem -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces" -ErrorAction SilentlyContinue | ForEach-Object {
            Set-ItemProperty -Path $_.PSPath -Name TcpAckFrequency -Value 1 -Type DWord -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $_.PSPath -Name TCPNoDelay -Value 1 -Type DWord -ErrorAction SilentlyContinue
        }
    }
    if ($config.POSOptimizations.FastBootTweaks) {
        bcdedit.exe /set "{current}" bootmenupolicy legacy 2>$null | Out-Null
        bcdedit.exe /set "{current}" bootuxdisabled on 2>$null | Out-Null
    }
    if ($config.POSOptimizations.RemoveVirtualPrinters) {
        foreach ($vp in @("Microsoft Print to PDF", "Microsoft XPS Document Writer", "OneNote (Desktop)", "OneNote for Windows 10", "Fax")) {
            Remove-Printer -Name $vp -ErrorAction SilentlyContinue
        }
    }
    if ($config.POSOptimizations.CleanDefaultUserShortcuts) {
        foreach ($ld in @("$env:PUBLIC\Desktop", "$env:ProgramData\Microsoft\Windows\Start Menu\Programs", "$env:USERPROFILE\Desktop")) {
            Get-ChildItem -Path $ld -Filter "*.lnk" -File -ErrorAction SilentlyContinue |
                Where-Object { $_.BaseName -match "Edge|OneDrive|Outlook|Teams|Copilot|Store" } |
                Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }
}

if ($config.Debloat.DisableUnnecessaryServices -and $config.Debloat.ServicesToDisable) {
    Write-Host "    [*] Disabling non-POS background services..." -ForegroundColor Cyan
    foreach ($svc in @($config.Debloat.ServicesToDisable)) {
        if (-not $svc) { continue }
        $svcKey = "HKLM\SYSTEM\CurrentControlSet\Services\$svc"
        reg.exe query $svcKey /v Start 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
            reg.exe add $svcKey /v Start /t REG_DWORD /d 4 /f 2>$null | Out-Null
        }
    }
}
if ($config.Debloat.RemoveEdge) {
    foreach ($edgeSvc in @("edgeupdate", "edgeupdatem", "MicrosoftEdgeElevationService")) {
        sc.exe delete $edgeSvc 2>$null | Out-Null
    }
}

if ($config.Debloat.DisableUnnecessaryServices) {
    foreach ($svc in @("SysMain", "WerSvc", "wercplsupport", "PcaSvc", "GameInputSvc", "PushToInstall", "Wisvc")) {
        if (Get-Service -Name $svc -ErrorAction SilentlyContinue) {
            Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
            Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
        }
    }
    if ($config.POSOptimizations -and $config.POSOptimizations.KeepSearchIndexer) {
        if (Get-Service -Name "WSearch" -ErrorAction SilentlyContinue) {
            Set-Service -Name "WSearch" -StartupType Automatic -ErrorAction SilentlyContinue
            Start-Service -Name "WSearch" -ErrorAction SilentlyContinue
        }
    }
}

# Post-OOBE Microsoft Store & Bloatware App Removal (Runs immediately in Step 1 so Store & bloatware are gone before app installers run)
Write-Host "    [*] Removing Microsoft Store & bloatware Windows apps (keeping Calculator, Notepad, Paint & Snipping Tool)..." -ForegroundColor Cyan
if ($config.Debloat.RemoveMicrosoftStore) {
    reg.exe add "HKCU\Software\Policies\Microsoft\WindowsStore" /v RemoveWindowsStore /t REG_DWORD /d 1 /f 2>$null | Out-Null
    reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\WindowsStore" /v RemoveWindowsStore /t REG_DWORD /d 1 /f 2>$null | Out-Null
    reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\WindowsStore" /v AutoDownload /t REG_DWORD /d 2 /f 2>$null | Out-Null
    reg.exe delete "HKLM\SOFTWARE\Policies\Microsoft\WindowsStore" /v DisableStoreApps /f 2>$null | Out-Null

    Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match "WindowsStore|StorePurchaseApp" -or $_.PackageName -match "WindowsStore|StorePurchaseApp" } |
        ForEach-Object { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null }

    Get-AppxPackage -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "WindowsStore|StorePurchaseApp" } |
        ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -ErrorAction SilentlyContinue | Out-Null }

    Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "WindowsStore|StorePurchaseApp" } |
        ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue | Out-Null }
}

if ($config.Debloat.AppxPackagesToRemove) {
    foreach ($pattern in $config.Debloat.AppxPackagesToRemove) {
        Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like "*$pattern*" -or $_.PackageName -like "*$pattern*" } |
            ForEach-Object { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null }

        Get-AppxPackage -Name "*$pattern*" -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-AppxPackage -Package $_.PackageFullName -ErrorAction SilentlyContinue | Out-Null
        }
        Get-AppxPackage -AllUsers -Name "*$pattern*" -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue | Out-Null
        }
    }
}

function Clear-PosStartMenuAds {
    if (-not $config.Debloat.ClearStartMenuPinnedAds) { return }

    $emptyPinsJson = '{"pinnedList":[]}'
    foreach ($polPath in @(
        "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Start",
        "HKLM:\SOFTWARE\Microsoft\PolicyManager\providers\B5292708-1619-419B-9923-E5D9F3925E71\default\Device\Start",
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer",
        "HKCU:\Software\Policies\Microsoft\Windows\Explorer"
    )) {
        if (-not (Test-Path $polPath)) {
            New-Item -Path $polPath -Force -ErrorAction SilentlyContinue | Out-Null
        }
    }

    # Write valid JSON {"pinnedList":[]} via Set-ItemProperty so quotes are never stripped by reg.exe
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Start" -Name "ConfigureStartPins" -Value $emptyPinsJson -ErrorAction SilentlyContinue
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Start" -Name "ConfigureStartPins_ProviderSet" -Value 1 -Type DWord -ErrorAction SilentlyContinue
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Start" -Name "ConfigureStartPins_WinningProvider" -Value "B5292708-1619-419B-9923-E5D9F3925E71" -ErrorAction SilentlyContinue
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Start" -Name "HideRecommendedSection" -Value 1 -Type DWord -ErrorAction SilentlyContinue
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\providers\B5292708-1619-419B-9923-E5D9F3925E71\default\Device\Start" -Name "ConfigureStartPins" -Value $emptyPinsJson -ErrorAction SilentlyContinue
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\providers\B5292708-1619-419B-9923-E5D9F3925E71\default\Device\Start" -Name "ConfigureStartPins_LastWrite" -Value 1 -Type DWord -ErrorAction SilentlyContinue
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name "ConfigureStartPinsJSON" -Value $emptyPinsJson -ErrorAction SilentlyContinue
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name "HideRecommendedSection" -Value 1 -Type DWord -ErrorAction SilentlyContinue
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name "HideRecommendedPersonalizedSites" -Value 1 -Type DWord -ErrorAction SilentlyContinue
    Set-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\Explorer" -Name "ConfigureStartPinsJSON" -Value $emptyPinsJson -ErrorAction SilentlyContinue
    Set-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\Explorer" -Name "HideRecommendedSection" -Value 1 -Type DWord -ErrorAction SilentlyContinue
    Set-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\Explorer" -Name "HideRecommendedPersonalizedSites" -Value 1 -Type DWord -ErrorAction SilentlyContinue

    # Clear cached Start Menu pinned stub tiles (start2.bin / pstart.bin) and layout policy state so StartMenu.dll re-applies ConfigureStartPins
    Stop-Process -Name "StartMenuExperienceHost" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Start" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\wsx\Windows.Shell.StartMenu" -Recurse -Force -ErrorAction SilentlyContinue
    $startPkgDir = Join-Path $env:LOCALAPPDATA "Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy"
    foreach ($sub in @("LocalState", "TempState")) {
        $dir = Join-Path $startPkgDir $sub
        if (Test-Path $dir) {
            Get-ChildItem -Path $dir -Filter "*start*.bin" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }
}

Clear-PosStartMenuAds

if ($config.Debloat.RemoveCopilotAndRecall) {
    reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowCopilotButton /t REG_DWORD /d 0 /f | Out-Null
    reg.exe add "HKCU\Software\Policies\Microsoft\Windows\WindowsCopilot" /v TurnOffWindowsCopilot /t REG_DWORD /d 1 /f | Out-Null
    foreach ($aiPol in @("HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI", "HKCU\Software\Policies\Microsoft\Windows\WindowsAI")) {
        reg.exe add $aiPol /v DisableAIDataAnalysis /t REG_DWORD /d 1 /f | Out-Null
        reg.exe add $aiPol /v TurnOffSavingSnapshots /t REG_DWORD /d 1 /f | Out-Null
        reg.exe add $aiPol /v AllowRecallEnablement /t REG_DWORD /d 0 /f | Out-Null
        reg.exe add $aiPol /v DisableClickToDo /t REG_DWORD /d 1 /f | Out-Null
        reg.exe add $aiPol /v DisableCocreator /t REG_DWORD /d 1 /f | Out-Null
        reg.exe add $aiPol /v DisableGenerativeFill /t REG_DWORD /d 1 /f | Out-Null
        reg.exe add $aiPol /v DisableImageCreator /t REG_DWORD /d 1 /f | Out-Null
    }
    reg.exe add "HKCU\Software\Policies\WindowsNotepad" /v DisableAIFeatures /t REG_DWORD /d 1 /f | Out-Null
    Get-WindowsOptionalFeature -Online -FeatureName "Recall" -ErrorAction SilentlyContinue |
        Where-Object { $_.State -eq "Enabled" } |
        ForEach-Object { Disable-WindowsOptionalFeature -Online -FeatureName "Recall" -Remove -NoRestart -ErrorAction SilentlyContinue | Out-Null }
}

if ($config.Debloat.DisableTelemetryAndAds) {
    reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v Start_IrisRecommendations /t REG_DWORD /d 0 /f | Out-Null
    reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v Start_AccountNotifications /t REG_DWORD /d 0 /f | Out-Null
    reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowSyncProviderNotifications /t REG_DWORD /d 0 /f | Out-Null
    reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.Suggested" /v Enabled /t REG_DWORD /d 0 /f | Out-Null
    reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" /v ScoobeSystemSettingEnabled /t REG_DWORD /d 0 /f | Out-Null
    reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" /v Enabled /t REG_DWORD /d 0 /f | Out-Null
    reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Privacy" /v TailoredExperiencesWithDiagnosticDataEnabled /t REG_DWORD /d 0 /f | Out-Null

    # Search Box Web Ads & Search Highlights
    reg.exe add "HKCU\Software\Policies\Microsoft\Windows\Explorer" /v DisableSearchBoxSuggestions /t REG_DWORD /d 1 /f | Out-Null
    reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Search" /v BingSearchEnabled /t REG_DWORD /d 0 /f | Out-Null
    reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\SearchSettings" /v IsDynamicSearchBoxEnabled /t REG_DWORD /d 0 /f | Out-Null
    reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\SearchSettings" /v IsDeviceSearchHistoryEnabled /t REG_DWORD /d 0 /f | Out-Null
    reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\SearchSettings" /v IsMSACloudSearchEnabled /t REG_DWORD /d 0 /f | Out-Null
    reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\SearchSettings" /v IsAADCloudSearchEnabled /t REG_DWORD /d 0 /f | Out-Null

    # CloudContent & Spotlight
    $userCloudPol = "HKCU\Software\Policies\Microsoft\Windows\CloudContent"
    reg.exe add $userCloudPol /v DisableTailoredExperiencesWithDiagnosticData /t REG_DWORD /d 1 /f | Out-Null
    reg.exe add $userCloudPol /v DisableThirdPartySuggestions /t REG_DWORD /d 1 /f | Out-Null
    reg.exe add $userCloudPol /v DisableWindowsSpotlightFeatures /t REG_DWORD /d 1 /f | Out-Null
    reg.exe add $userCloudPol /v ConfigureWindowsSpotlight /t REG_DWORD /d 2 /f | Out-Null
    reg.exe add $userCloudPol /v IncludeEnterpriseSpotlight /t REG_DWORD /d 0 /f | Out-Null
    reg.exe add $userCloudPol /v DisableWindowsSpotlightOnActionCenter /t REG_DWORD /d 1 /f | Out-Null
    reg.exe add $userCloudPol /v DisableWindowsSpotlightOnSettings /t REG_DWORD /d 1 /f | Out-Null
    reg.exe add $userCloudPol /v DisableWindowsSpotlightWindowsWelcomeExperience /t REG_DWORD /d 1 /f | Out-Null

    # ContentDeliveryManager
    $cdmKey = "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    $cdmValues = @(
        "ContentDeliveryAllowed",
        "FeatureManagementEnabled",
        "OemPreInstalledAppsEnabled",
        "PreInstalledAppsEnabled",
        "PreInstalledAppsEverEnabled",
        "SilentInstalledAppsEnabled",
        "SoftLandingEnabled",
        "SubscribedContentEnabled",
        "SystemPaneSuggestionsEnabled",
        "RotatingLockScreenEnabled",
        "RotatingLockScreenOverlayEnabled",
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
        "SubscribedContent-88000326Enabled"
    )
    foreach ($val in $cdmValues) {
        reg.exe add $cdmKey /v $val /t REG_DWORD /d 0 /f | Out-Null
    }
    reg.exe delete "$cdmKey\SuggestedApps" /f 2>$null | Out-Null
    reg.exe delete "$cdmKey\Subscriptions" /f 2>$null | Out-Null
}

# GeoID, Regional (English - Cyprus), Only US Keyboard, Currency (" ") & 24-Hour Time
function Apply-PosRegionalSettings {
    if ($config.Regional.GeoId) {
        Set-WinHomeLocation -GeoId ([int]$config.Regional.GeoId) -ErrorAction SilentlyContinue
    }
    if ($config.Regional.TimeZone) {
        Set-TimeZone -Id $config.Regional.TimeZone -ErrorAction SilentlyContinue
    }

    # Prevent Windows Language Profile sync from overwriting custom Regional Format (en-CY) settings
    Set-WinCultureFromLanguageListOptOut -OptOut $true -ErrorAction SilentlyContinue

    # Apply base Regional Format (en-CY) first
    if ($config.Regional.UserLocale) {
        Set-Culture -CultureInfo $config.Regional.UserLocale -ErrorAction SilentlyContinue
    }

    # Override Short Date (dd/MM/yyyy), Currency Symbol (" ") and 24-Hour Time (HH:mm / HH:mm:ss)
    # via Win32 SetLocaleInfoW + Registry + Cloud Data Store Sync
    $localeName  = if ($config.Regional.UserLocale)      { [string]$config.Regional.UserLocale }      else { "en-CY" }
    $currencySym = if ($null -ne $config.Regional.CurrencySymbol) { [string]$config.Regional.CurrencySymbol } else { " " }
    $shortDate   = if ($config.Regional.ShortDateFormat) { [string]$config.Regional.ShortDateFormat } else { "dd/MM/yyyy" }
    $shortTime   = if ($config.Regional.ShortTimeFormat) { [string]$config.Regional.ShortTimeFormat } else { "HH:mm" }
    $longTime    = if ($config.Regional.LongTimeFormat)  { [string]$config.Regional.LongTimeFormat }  else { "HH:mm:ss" }

    try {
        if (-not ("TinyWinNls" -as [type])) {
            Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class TinyWinNls {
    [DllImport("kernelbase.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    public static extern int NlsUpdateLocale(string LocaleName, int Flags);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool SetLocaleInfoW(uint Locale, uint LCType, string lpLCData);

    [DllImport("coreglobconfig.dll", ExactSpelling = true)]
    public static extern int SyncLanguageDataToCloudSynchronous();

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern IntPtr SendNotifyMessage(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam);

    public static void ApplyPosRegional(string localeName, string currency, string shortDate, string shortTime, string longTime, bool use24h) {
        const uint LOCALE_USER_DEFAULT = 0x0400;
        try { NlsUpdateLocale(localeName, 0); } catch {}
        SetLocaleInfoW(LOCALE_USER_DEFAULT, 0x00000014, currency);      // LOCALE_SCURRENCY (" ")
        SetLocaleInfoW(LOCALE_USER_DEFAULT, 0x0000001D, "/");           // LOCALE_SDATE ("/")
        SetLocaleInfoW(LOCALE_USER_DEFAULT, 0x00000021, "1");           // LOCALE_IDATE (1 = dd/MM/yyyy)
        SetLocaleInfoW(LOCALE_USER_DEFAULT, 0x0000001F, shortDate);     // LOCALE_SSHORTDATE ("dd/MM/yyyy")
        SetLocaleInfoW(LOCALE_USER_DEFAULT, 0x0000100C, "0");           // LOCALE_IFIRSTDAYOFWEEK (0 = Monday)
        if (use24h) {
            SetLocaleInfoW(LOCALE_USER_DEFAULT, 0x00000023, "1");       // LOCALE_ITIME (24-hour)
            SetLocaleInfoW(LOCALE_USER_DEFAULT, 0x00000025, "1");       // LOCALE_ITLZERO (leading zero)
            SetLocaleInfoW(LOCALE_USER_DEFAULT, 0x00001005, "0");       // LOCALE_ITIMEMARKPOSN
            SetLocaleInfoW(LOCALE_USER_DEFAULT, 0x00000079, shortTime); // LOCALE_SSHORTTIME ("HH:mm")
            SetLocaleInfoW(LOCALE_USER_DEFAULT, 0x00001003, longTime);  // LOCALE_STIMEFORMAT ("HH:mm:ss")
        }
        try { SyncLanguageDataToCloudSynchronous(); } catch {}
        SendNotifyMessage((IntPtr)0xFFFF, 0x001A, UIntPtr.Zero, "intl");
    }

    public static void BroadcastAndSync() {
        try { SyncLanguageDataToCloudSynchronous(); } catch {}
        SendNotifyMessage((IntPtr)0xFFFF, 0x001A, UIntPtr.Zero, "intl");
    }
}
"@ -ErrorAction SilentlyContinue
        }
        [TinyWinNls]::ApplyPosRegional($localeName, $currencySym, $shortDate, $shortTime, $longTime, [bool]$config.Regional.Use24HourTime)
    } catch {}

    Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name "LocaleName"      -Value $localeName  -ErrorAction SilentlyContinue
    Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name "Locale"          -Value "00000C00"   -ErrorAction SilentlyContinue
    Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name "sCurrency"       -Value $currencySym -ErrorAction SilentlyContinue
    Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name "sShortDate"      -Value $shortDate   -ErrorAction SilentlyContinue
    Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name "sDate"           -Value "/"          -ErrorAction SilentlyContinue
    Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name "iDate"           -Value "1"          -ErrorAction SilentlyContinue
    Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name "iFirstDayOfWeek" -Value "0"          -ErrorAction SilentlyContinue
    if ($config.Regional.Use24HourTime) {
        Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name "iTime"       -Value "1"        -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name "iTLZero"     -Value "1"        -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name "iTimePrefix" -Value "0"        -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name "sShortTime"  -Value $shortTime -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name "sTimeFormat" -Value $longTime  -ErrorAction SilentlyContinue
    }
    try { [TinyWinNls]::BroadcastAndSync() } catch {}

    # Copy customized international settings to Welcome Screen (HKU\.DEFAULT) and New User accounts
    Copy-UserInternationalSettingsToSystem -WelcomeScreen $true -NewUser $true -ErrorAction SilentlyContinue
}

# Enforce ONLY English (US) Keyboard Layout (0409:00000409)
try {
    Set-WinCultureFromLanguageListOptOut -OptOut $true -ErrorAction SilentlyContinue
    $langList = New-WinUserLanguageList -Language "en-US"
    $langList[0].InputMethodTips.Clear()
    $langList[0].InputMethodTips.Add("0409:00000409")
    Set-WinUserLanguageList -LanguageList $langList -Force -ErrorAction SilentlyContinue
} catch {}

reg.exe delete "HKCU\Keyboard Layout\Preload" /f 2>$null | Out-Null
reg.exe add "HKCU\Keyboard Layout\Preload" /v "1" /t REG_SZ /d "00000409" /f 2>$null | Out-Null
reg.exe delete "HKCU\Keyboard Layout\Substitutes" /f 2>$null | Out-Null
reg.exe add "HKCU\Keyboard Layout\Substitutes" /f 2>$null | Out-Null

Apply-PosRegionalSettings

# Custom Wallpaper
$customWall = "C:\Windows\Web\Wallpaper\Windows\tinywin_wallpaper.jpg"
if (-not (Test-Path $customWall)) {
    $customWall = "C:\Windows\Web\Wallpaper\Windows\img0.jpg"
}
if (Test-Path $customWall) {
    reg.exe add "HKCU\Control Panel\Desktop" /v Wallpaper /t REG_SZ /d "$customWall" /f | Out-Null
    reg.exe add "HKCU\Control Panel\Desktop" /v WallpaperStyle /t REG_SZ /d "10" /f | Out-Null
    try {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class WallpaperSetter {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@ -ErrorAction SilentlyContinue
        [WallpaperSetter]::SystemParametersInfo(0x0014, 0, $customWall, 0x01 -bor 0x02) | Out-Null
    } catch {}
}

# ---------------------------------------------------------------------------
# 2. Install Offline Bundled Applications (MeshCentral & Custom Installers)
# ---------------------------------------------------------------------------
Write-Host "`n[2/4] Checking Offline Bundled Installers in $InstallDir..." -ForegroundColor Yellow

$handledFiles = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)

if (Test-Path $InstallDir) {
    if ($config.Applications.OfflineInstallers) {
        foreach ($installer in $config.Applications.OfflineInstallers) {
            $handledFiles.Add($installer.FileName) | Out-Null
            if (-not $installer.Enabled) { continue }

            $exePath = Join-Path $InstallDir $installer.FileName
            if (-not (Test-Path $exePath)) {
                Write-Host "    [Skipped] $($installer.FileName) is not present in $InstallDir" -ForegroundColor DarkGray
                continue
            }

            # If it was a SetupComplete installer (e.g. meshagent.exe), verify if service is already running
            if ($installer.RunStage -eq "SetupComplete" -and $installer.FileName -match "meshagent") {
                if (Get-Service -Name "Mesh Agent" -ErrorAction SilentlyContinue) {
                    Write-Host "    [OK] MeshCentral Agent service is already installed and running." -ForegroundColor Green
                    continue
                }
            }

            Write-Host "    [*] Installing $($installer.Description) ($($installer.FileName))..." -ForegroundColor Cyan
            try {
                if (-not [string]::IsNullOrWhiteSpace($installer.Arguments)) {
                    $proc = Start-Process -FilePath $exePath -ArgumentList $installer.Arguments -Wait -PassThru
                } else {
                    $proc = Start-Process -FilePath $exePath -Wait -PassThru
                }
                Write-Host "        Finished with exit code: $($proc.ExitCode)" -ForegroundColor Green
            } catch {
                Write-Warning "        Error running $($installer.FileName): $_"
            }
        }
    }

    # Auto-install any additional .msi / .msix / .exe dropped into apps/installers/
    if ($config.Applications.AutoInstallAllInFolder) {
        $extraFiles = Get-ChildItem -Path $InstallDir -File | Where-Object {
            $_.Extension -in @(".exe", ".msi", ".msix", ".msixbundle") -and -not $handledFiles.Contains($_.Name)
        }
        foreach ($file in $extraFiles) {
            Write-Host "    [*] Auto-installing bundled file: $($file.Name)..." -ForegroundColor Cyan
            try {
                switch ($file.Extension.ToLower()) {
                    ".msi" {
                        Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$($file.FullName)`" /qn /norestart" -Wait
                    }
                    { $_ -in @(".msix", ".msixbundle") } {
                        Add-AppxPackage -Path $file.FullName -ErrorAction Continue
                    }
                    ".exe" {
                        # If it looks like a MeshCentral binary (e.g. meshagent-*.exe), use -fullinstall
                        $arg = if ($file.Name -match "meshagent") { "-fullinstall" } else { "/S" }
                        Start-Process -FilePath $file.FullName -ArgumentList $arg -Wait
                    }
                }
                Write-Host "        Done: $($file.Name)" -ForegroundColor Green
            } catch {
                Write-Warning "        Failed to auto-install $($file.Name): $_"
            }
        }
    }
}

# ---------------------------------------------------------------------------
# 3. Helper Function for Winget + Direct Official Fallback Download
# ---------------------------------------------------------------------------
function Resolve-WingetPath {
    $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $userApp = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\winget.exe"
    if (Test-Path $userApp) { return $userApp }

    $sysApp = Get-ChildItem -Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction SilentlyContinue |
              Sort-Object LastWriteTime -Descending |
              Select-Object -First 1
    if ($sysApp) { return $sysApp.FullName }

    return $null
}

function Install-FallbackDirect {
    param([string]$PackageId)

    $tempDir = Join-Path $env:TEMP "TinyWinDownloads"
    if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir -Force | Out-Null }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    switch ($PackageId) {
        "Microsoft.VCRedist.2015+.x64" {
            $url = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
            $out = Join-Path $tempDir "vc_redist.x64.exe"
            Write-Host "        [Fallback] Downloading VC++ Redistributable x64 from Microsoft..." -ForegroundColor DarkCyan
            Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing
            Start-Process -FilePath $out -ArgumentList "/install /quiet /norestart" -Wait
            return $true
        }
        "Microsoft.VCRedist.2015+.x86" {
            $url = "https://aka.ms/vs/17/release/vc_redist.x86.exe"
            $out = Join-Path $tempDir "vc_redist.x86.exe"
            Write-Host "        [Fallback] Downloading VC++ Redistributable x86 from Microsoft..." -ForegroundColor DarkCyan
            Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing
            Start-Process -FilePath $out -ArgumentList "/install /quiet /norestart" -Wait
            return $true
        }
        "TeamViewer.TeamViewer" {
            $url = "https://download.teamviewer.com/download/TeamViewer_Setup_x64.exe"
            $out = Join-Path $tempDir "TeamViewer_Setup_x64.exe"
            Write-Host "        [Fallback] Downloading TeamViewer x64 from official CDN..." -ForegroundColor DarkCyan
            Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing
            $proc = Start-Process -FilePath $out -ArgumentList "/S" -PassThru
            if ($proc) { $null = $proc.WaitForExit(120000) }
            return $true
        }
        "LibreWolf.LibreWolf" {
            Write-Host "        [Fallback] Querying latest LibreWolf x64 installer..." -ForegroundColor DarkCyan
            try {
                $release = Invoke-RestMethod -Uri "https://codeberg.org/api/v1/repos/librewolf/bsys6/releases/latest" -Headers @{ "User-Agent" = "TinyWin11Builder" }
                $asset = $release.assets | Where-Object { $_.name -match "windows-x86_64-setup\.exe$" } | Select-Object -First 1
                if ($asset) {
                    $out = Join-Path $tempDir $asset.name
                    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $out -UseBasicParsing
                    $proc = Start-Process -FilePath $out -ArgumentList "/S" -PassThru
                    if ($proc) { $null = $proc.WaitForExit(120000) }
                    return $true
                }
            } catch {}
            try {
                $glReleases = Invoke-RestMethod -Uri "https://gitlab.com/api/v4/projects/44042130/releases" -Headers @{ "User-Agent" = "TinyWin11Builder" }
                $glLink = $glReleases[0].assets.links | Where-Object { $_.name -match "windows-x86_64-setup\.exe$" } | Select-Object -First 1
                if ($glLink) {
                    $out = Join-Path $tempDir $glLink.name
                    Invoke-WebRequest -Uri $glLink.direct_asset_url -OutFile $out -UseBasicParsing
                    $proc = Start-Process -FilePath $out -ArgumentList "/S" -PassThru
                    if ($proc) { $null = $proc.WaitForExit(120000) }
                    return $true
                }
            } catch {}
            return $false
        }
    }
    return $false
}

# ---------------------------------------------------------------------------
# 4. Install Pre-Configured Applications (Pre-Cached or Online Winget/Direct)
# ---------------------------------------------------------------------------
Write-Host "`n[3/4] Installing Pre-Configured Applications (VC++ Redists, LibreWolf, TeamViewer)..." -ForegroundColor Yellow

$wingetExe = Resolve-WingetPath
if ($wingetExe) {
    Write-Host "    Found Winget at: $wingetExe" -ForegroundColor Gray
} else {
    Write-Host "    Winget binary not immediately ready; will use pre-cached installers or direct official downloads." -ForegroundColor DarkYellow
}

foreach ($pkg in $config.Applications.WingetPackages) {
    if (-not $pkg.Enabled) { continue }

    Write-Host "    [*] Installing $($pkg.Name) [$($pkg.Id)]..." -ForegroundColor Cyan
    $installed = $false

    # Check if pre-downloaded in WingetCache folder during ISO build
    $pkgCacheDir = Join-Path $CacheDir $pkg.Id
    if (Test-Path $pkgCacheDir) {
        $cachedInstaller = Get-ChildItem -Path $pkgCacheDir -File | Where-Object { $_.Extension -in @(".exe", ".msi", ".msix") } | Select-Object -First 1
        if ($cachedInstaller) {
            Write-Host "        Found offline cached installer: $($cachedInstaller.Name)" -ForegroundColor Green
            try {
                if ($cachedInstaller.Extension -eq ".msi") {
                    $proc = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$($cachedInstaller.FullName)`" /qn /norestart" -PassThru
                } elseif ($pkg.Id -match "VCRedist\.(2005|2008)") {
                    # IExpress-based redists only understand /q
                    $proc = Start-Process -FilePath $cachedInstaller.FullName -ArgumentList "/q" -PassThru
                } elseif ($pkg.Id -match "VCRedist\.2010") {
                    $proc = Start-Process -FilePath $cachedInstaller.FullName -ArgumentList "/q /norestart" -PassThru
                } elseif ($pkg.Id -match "VCRedist") {
                    $proc = Start-Process -FilePath $cachedInstaller.FullName -ArgumentList "/install /quiet /norestart" -PassThru
                } else {
                    $proc = Start-Process -FilePath $cachedInstaller.FullName -ArgumentList "/S" -PassThru
                }
                if ($proc) { $null = $proc.WaitForExit(120000) }
                $installed = $true
                Write-Host "        Finished installing $($pkg.Name)." -ForegroundColor Green
            } catch {
                Write-Warning "        Cached installer failed: $_"
            }
        }
    }

    # Try Winget online install if not already installed from cache
    if (-not $installed -and $wingetExe) {
        try {
            $proc = Start-Process -FilePath $wingetExe -ArgumentList "install --id `"$($pkg.Id)`" --exact --source winget --accept-package-agreements --accept-source-agreements --silent --disable-interactivity" -Wait -PassThru -NoNewWindow
            if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq -1978335189) {
                $installed = $true
                Write-Host "        Installed $($pkg.Name) via Winget." -ForegroundColor Green
            } else {
                Write-Warning "        Winget returned exit code $($proc.ExitCode) for $($pkg.Id). Trying direct download fallback..."
            }
        } catch {
            Write-Warning "        Winget execution failed: $_"
        }
    }

    # Direct official fallback downloader if Winget failed or wasn't ready
    if (-not $installed) {
        try {
            if (Install-FallbackDirect -PackageId $pkg.Id) {
                Write-Host "        Installed $($pkg.Name) via Direct Official Fallback." -ForegroundColor Green
            } else {
                Write-Warning "        Could not install $($pkg.Name). Check internet connection."
            }
        } catch {
            Write-Warning "        Direct download fallback failed for $($pkg.Name): $_"
        }
    }
}

Write-Host "`n[4/4] Finalizing Store/Ad Cleanup & Restarting Shell..." -ForegroundColor Yellow

# Remove any residual user-level Microsoft Edge shortcuts
if ($config.Debloat.RemoveEdge) {
    $userEdgeShortcuts = @(
        (Join-Path $env:USERPROFILE "Desktop\Microsoft Edge.lnk"),
        (Join-Path $env:APPDATA "Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\Microsoft Edge.lnk"),
        (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk")
    )
    foreach ($lnk in $userEdgeShortcuts) {
        if (Test-Path $lnk) {
            Remove-Item -Path $lnk -Force -ErrorAction SilentlyContinue
        }
    }
}

# Remove any residual user-provisioned Store bloatware packages
if ($config.Debloat.AppxPackagesToRemove) {
    foreach ($pattern in $config.Debloat.AppxPackagesToRemove) {
        Get-AppxPackage -Name "*$pattern*" -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-AppxPackage -Package $_.PackageFullName -ErrorAction SilentlyContinue | Out-Null
        }
        Get-AppxPackage -AllUsers -Name "*$pattern*" -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue | Out-Null
        }
    }
}

# Re-enforce Regional Format (en-CY), Short Date (dd/MM/yyyy), Currency (" ") & 24-Hour Time right before restarting Explorer
Apply-PosRegionalSettings

# Re-enforce clean Start Menu pins & wipe any regenerated start2.bin before restarting Explorer
Clear-PosStartMenuAds
Stop-Process -Name "SearchHost" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "Widgets" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
if (-not (Get-Process -Name "explorer" -ErrorAction SilentlyContinue)) {
    Start-Process "explorer.exe"
}

Write-Host "`n[+] TinyWin 11 Provisioning Complete!" -ForegroundColor Green
Stop-Transcript
