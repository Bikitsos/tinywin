<#
.SYNOPSIS
    Runs as SYSTEM at the end of Windows Setup (before OOBE user logon).
    Keeps pre-OOBE actions strictly minimal and OOBE-safe (Computer Name, Branding,
    Power Plan, and MeshCentral agent). All Store removal, UI, and POS lockdown
    policies run in FirstLogon.ps1 AFTER OOBE has completed cleanly.
#>
$ErrorActionPreference = "Continue"

$TinyWinRoot = "C:\TinyWin"
$LogDir      = Join-Path $TinyWinRoot "Logs"
$ConfigPath  = Join-Path $TinyWinRoot "config.json"
$InstallDir  = Join-Path $TinyWinRoot "Apps\Installers"

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

Start-Transcript -Path (Join-Path $LogDir "SetupComplete.log") -Append

Write-Host "=== TinyWin 11 SetupComplete Started ($(Get-Date)) ===" -ForegroundColor Cyan

if (Test-Path $ConfigPath) {
    $config = Get-Content -Path $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json

    # 0. Ensure computer name is POS + random numbers (no dash or special chars) before MeshCentral installs
    if (-not [string]::IsNullOrWhiteSpace($config.Branding.ComputerNamePrefix)) {
        $prefix = $config.Branding.ComputerNamePrefix -replace '[^a-zA-Z0-9]', ''
        $digits = if ($config.Branding.ComputerNameRandomDigits -gt 0) { [int]$config.Branding.ComputerNameRandomDigits } else { 6 }
        if ($env:COMPUTERNAME -notmatch "^$prefix\d+$") {
            $newHost = $prefix + -join ((1..$digits) | ForEach-Object { Get-Random -Minimum 0 -Maximum 10 })
            Write-Host "[*] Setting Computer Name to: $newHost" -ForegroundColor Cyan
            Rename-Computer -NewName $newHost -Force -ErrorAction SilentlyContinue
            reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName" /v ComputerName /t REG_SZ /d "$newHost" /f | Out-Null
            reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName" /v ComputerName /t REG_SZ /d "$newHost" /f | Out-Null
            reg.exe add "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v "Hostname" /t REG_SZ /d "$newHost" /f | Out-Null
            reg.exe add "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v "NV Hostname" /t REG_SZ /d "$newHost" /f | Out-Null
        } else {
            Write-Host "[*] Computer Name is already set to: $env:COMPUTERNAME" -ForegroundColor Green
        }
    }

    # Ensure OS Edition / Branding Name ("POS READY 2026") is set in Registry & Boot Manager
    if (-not [string]::IsNullOrWhiteSpace($config.Branding.OSName)) {
        $osName = $config.Branding.OSName
        reg.exe add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v ProductName /t REG_SZ /d "$osName" /f | Out-Null
        reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation" /v Model /t REG_SZ /d "$osName" /f | Out-Null
        reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation" /v Manufacturer /t REG_SZ /d "$($config.Branding.Manufacturer)" /f | Out-Null
        bcdedit.exe /set "{current}" description "$osName" 2>$null | Out-Null
    }

    # Ensure passwordless user account never expires
    net.exe accounts /maxpwage:unlimited 2>$null | Out-Null
    if ($config.UserAccount.DefaultUsername) {
        Set-LocalUser -Name $config.UserAccount.DefaultUsername -PasswordNeverExpires $true -ErrorAction SilentlyContinue
    }

    # 0b. Apply OOBE-Safe POS Power, USB, Lock Screen, Blank-Password LAN & Windows Update Optimizations
    if ($config.POSOptimizations) {
        if ($config.POSOptimizations.NeverSleepAndHighPerformance) {
            Write-Host "[*] Configuring POS 24/7 High Performance Power Plan (Never Sleep / Never Turn Off Screen)..." -ForegroundColor Cyan
            powercfg.exe /hibernate off 2>$null | Out-Null
            powercfg.exe /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null | Out-Null
            powercfg.exe /change standby-timeout-ac 0 2>$null | Out-Null
            powercfg.exe /change standby-timeout-dc 0 2>$null | Out-Null
            powercfg.exe /change monitor-timeout-ac 0 2>$null | Out-Null
            powercfg.exe /change monitor-timeout-dc 0 2>$null | Out-Null
            powercfg.exe /change disk-timeout-ac 0 2>$null | Out-Null
            powercfg.exe /change disk-timeout-dc 0 2>$null | Out-Null
        }
        if ($config.POSOptimizations.DisableUSBSelectiveSuspend) {
            Write-Host "[*] Disabling USB Selective Suspend for POS Peripherals (Printers/Scanners/Terminals)..." -ForegroundColor Cyan
            powercfg.exe /SETACVALUEINDEX SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>$null | Out-Null
            powercfg.exe /SETDCVALUEINDEX SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>$null | Out-Null
            powercfg.exe /SETACTIVE SCHEME_CURRENT 2>$null | Out-Null
        }
        if ($config.POSOptimizations.AllowBlankPasswordNetworkAccess) {
            reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v LimitBlankPasswordUse /t REG_DWORD /d 0 /f | Out-Null
        }
        if ($config.POSOptimizations.DisableLockScreen) {
            reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Personalization" /v NoLockScreen /t REG_DWORD /d 1 /f | Out-Null
        }
        if ($config.POSOptimizations.DisableWindowsUpdateAutoReboot) {
            reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v NoAutoRebootWithLoggedOnUsers /t REG_DWORD /d 1 /f | Out-Null
            reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v AUOptions /t REG_DWORD /d 3 /f | Out-Null
        }
        if ($config.POSOptimizations.DisableUSBSelectiveSuspend) {
            reg.exe add "HKLM\SYSTEM\CurrentControlSet\Services\USB" /v DisableSelectiveSuspend /t REG_DWORD /d 1 /f | Out-Null
        }
        if ($config.POSOptimizations.DisableReservedStorageAndHibernation) {
            reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power" /v HiberbootEnabled /t REG_DWORD /d 0 /f | Out-Null
        }
        if ($config.POSOptimizations.EnableNetworkDeviceDiscoveryServices) {
            Write-Host "[*] Enabling WSD/UPnP discovery services for network printers..." -ForegroundColor Cyan
            foreach ($svc in @("fdPHost", "FDResPub", "SSDPSRV", "upnphost")) {
                if (Get-Service -Name $svc -ErrorAction SilentlyContinue) {
                    Set-Service -Name $svc -StartupType Automatic -ErrorAction SilentlyContinue
                    Start-Service -Name $svc -ErrorAction SilentlyContinue
                }
            }
        }
        if ($config.POSOptimizations.DisableAutoPlay) {
            reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v NoDriveTypeAutoRun /t REG_DWORD /d 255 /f | Out-Null
            reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Explorer" /v NoAutoplayfornonVolume /t REG_DWORD /d 1 /f | Out-Null
        }
        if ($config.POSOptimizations.DisableDeliveryOptimization) {
            reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" /v DODownloadMode /t REG_DWORD /d 0 /f | Out-Null
        }
        if ($config.POSOptimizations.PinFeatureRelease) {
            $wuPol = "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
            reg.exe add $wuPol /v TargetReleaseVersion /t REG_DWORD /d 1 /f | Out-Null
            reg.exe add $wuPol /v ProductVersion /t REG_SZ /d "Windows 11" /f | Out-Null
            reg.exe add $wuPol /v TargetReleaseVersionInfo /t REG_SZ /d "$($config.POSOptimizations.PinFeatureRelease)" /f | Out-Null
        }
        if ($config.POSOptimizations.ForegroundPriorityBoost) {
            reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\PriorityControl" /v Win32PrioritySeparation /t REG_DWORD /d 0x26 /f | Out-Null
        }
        # NOTE: SetupComplete runs BEFORE the OOBE UI. Service disabling, scheduled-task changes, pagefile, NTFS,
        # bcdedit, Defender and printer changes are applied in FirstLogon.ps1 (post-OOBE) to avoid
        # CloudExperienceHost failing with "Why did my PC restart?".
    }

    # 0c. Apply Start Menu Empty Pins & Recommended Hide as SYSTEM before user profile creation
    if ($config.Debloat.ClearStartMenuPinnedAds) {
        $emptyPinsJson = '{"pinnedList":[]}'
        foreach ($polPath in @(
            "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Start",
            "HKLM:\SOFTWARE\Microsoft\PolicyManager\providers\B5292708-1619-419B-9923-E5D9F3925E71\default\Device\Start",
            "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"
        )) {
            if (-not (Test-Path $polPath)) {
                New-Item -Path $polPath -Force -ErrorAction SilentlyContinue | Out-Null
            }
        }
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Start" -Name "ConfigureStartPins" -Value $emptyPinsJson -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Start" -Name "ConfigureStartPins_ProviderSet" -Value 1 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Start" -Name "ConfigureStartPins_WinningProvider" -Value "B5292708-1619-419B-9923-E5D9F3925E71" -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Start" -Name "HideRecommendedSection" -Value 1 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\providers\B5292708-1619-419B-9923-E5D9F3925E71\default\Device\Start" -Name "ConfigureStartPins" -Value $emptyPinsJson -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\providers\B5292708-1619-419B-9923-E5D9F3925E71\default\Device\Start" -Name "ConfigureStartPins_LastWrite" -Value 1 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name "ConfigureStartPinsJSON" -Value $emptyPinsJson -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name "HideRecommendedSection" -Value 1 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name "HideRecommendedPersonalizedSites" -Value 1 -Type DWord -ErrorAction SilentlyContinue
    }

    # 1. Disable basic telemetry services & tasks (OOBE-safe subset)
    if ($config.Debloat.DisableUnnecessaryServices) {
        Write-Host "[*] Optimizing background services..."
        $servicesToDisable = @(
            "DiagTrack",           # Connected User Experiences and Telemetry
            "dmwappushservice",    # WAP Push Message Routing Service (Telemetry)
            "MapsBroker",          # Downloaded Maps Manager
            "lfsvc",               # Geolocation Service (optional)
            "RetailDemo",          # Retail Demo Service
            "XblAuthManager",      # Xbox Live Auth Manager
            "XblGameSave",         # Xbox Live Game Save
            "XboxGipSvc",          # Xbox Accessory Management Service
            "XboxNetApiSvc"        # Xbox Live Networking Service
        )
        foreach ($svc in $servicesToDisable) {
            if (Get-Service -Name $svc -ErrorAction SilentlyContinue) {
                Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
                Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
                Write-Host "    Disabled service: $svc"
            }
        }
        # Debloat.ServicesToDisable is applied post-OOBE in FirstLogon.ps1
    }
    if ($config.Debloat.RemoveEdge) {
        foreach ($edgeTask in @("MicrosoftEdgeUpdateTaskMachineCore", "MicrosoftEdgeUpdateTaskMachineUA")) {
            schtasks.exe /Delete /TN "$edgeTask" /F 2>$null | Out-Null
        }
    }
    # Stop Windows Update Orchestrator from re-installing new Outlook / Dev Home after OOBE
    foreach ($uso in @("OutlookUpdate", "DevHomeUpdate")) {
        reg.exe delete "HKLM\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe" /v $uso /f 2>$null | Out-Null
    }

    if ($config.Debloat.DisableTelemetryAndAds) {
        Write-Host "[*] Disabling telemetry scheduled tasks..."
        $tasksToDisable = @(
            "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
            "\Microsoft\Windows\Application Experience\ProgramDataUpdater",
            "\Microsoft\Windows\Autochk\Proxy",
            "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
            "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
            "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector"
        )
        foreach ($task in $tasksToDisable) {
            schtasks.exe /Change /TN "$task" /Disable 2>$null | Out-Null
        }
    }

    # 2. Run Offline Installers configured for SetupComplete stage (e.g. MeshCentral Agent)
    if ($config.Applications.OfflineInstallers) {
        foreach ($installer in $config.Applications.OfflineInstallers) {
            if ($installer.Enabled -and $installer.RunStage -eq "SetupComplete") {
                $exePath = Join-Path $InstallDir $installer.FileName
                if (Test-Path $exePath) {
                    Write-Host "[*] Installing $($installer.Description) ($($installer.FileName))..." -ForegroundColor Yellow
                    try {
                        $argsList = if ([string]::IsNullOrWhiteSpace($installer.Arguments)) { @() } else { $installer.Arguments }
                        if ($argsList) {
                            $proc = Start-Process -FilePath $exePath -ArgumentList $argsList -Wait -PassThru -WindowStyle Hidden
                        } else {
                            $proc = Start-Process -FilePath $exePath -Wait -PassThru -WindowStyle Hidden
                        }
                        Write-Host "    Completed with exit code: $($proc.ExitCode)" -ForegroundColor Green
                    } catch {
                        Write-Warning "    Failed to install $($installer.FileName): $_"
                    }
                } else {
                    Write-Host "    [Skipped] $($installer.FileName) not found in $InstallDir" -ForegroundColor DarkGray
                }
            }
        }
    }
}

Write-Host "=== TinyWin 11 SetupComplete Finished ($(Get-Date)) ===" -ForegroundColor Cyan
Stop-Transcript
