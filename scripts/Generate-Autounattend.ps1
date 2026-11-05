<#
.SYNOPSIS
    Generates a customized Windows 11 autounattend.xml file from config.json.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $PSScriptRoot "..\config.json"
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $PSScriptRoot "..\autounattend.xml"
}

if (-not (Test-Path $ConfigPath)) {
    throw "Configuration file not found at: $ConfigPath"
}

$config = Get-Content -Path $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json

# Build WinPE International block only if KeepSetupLanguagePrompt is false
$winPeIntlXml = ""
if (-not $config.Regional.KeepSetupLanguagePrompt) {
    $uiLang = $config.Regional.FallbackUILanguage
    $sysLocale = $config.Regional.SystemLocale
    $usrLocale = $config.Regional.UserLocale
    $inLocale = $config.Regional.InputLocale
    $winPeIntlXml = @"
        <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <SetupUILanguage>
                <UILanguage>$uiLang</UILanguage>
            </SetupUILanguage>
            <InputLocale>$inLocale</InputLocale>
            <SystemLocale>$sysLocale</SystemLocale>
            <UILanguage>$uiLang</UILanguage>
            <UserLocale>$usrLocale</UserLocale>
        </component>
"@
}

# Build RunSynchronous commands for WinPE hardware bypasses
$winPeCommands = New-Object System.Collections.Generic.List[string]
$order = 1

if ($config.Bypasses.BypassTPMAndSecureBoot) {
    $winPeCommands.Add(@"
                <RunSynchronousCommand wcm:action="add">
                    <Order>$order</Order>
                    <Path>reg.exe add "HKLM\SYSTEM\Setup\LabConfig" /v BypassTPMCheck /t REG_DWORD /d 1 /f</Path>
                </RunSynchronousCommand>
"@)
    $order++
    $winPeCommands.Add(@"
                <RunSynchronousCommand wcm:action="add">
                    <Order>$order</Order>
                    <Path>reg.exe add "HKLM\SYSTEM\Setup\LabConfig" /v BypassSecureBootCheck /t REG_DWORD /d 1 /f</Path>
                </RunSynchronousCommand>
"@)
    $order++
}

if ($config.Bypasses.BypassRAMCheck) {
    $winPeCommands.Add(@"
                <RunSynchronousCommand wcm:action="add">
                    <Order>$order</Order>
                    <Path>reg.exe add "HKLM\SYSTEM\Setup\LabConfig" /v BypassRAMCheck /t REG_DWORD /d 1 /f</Path>
                </RunSynchronousCommand>
"@)
    $order++
}

if ($config.Bypasses.BypassCPUCheck) {
    $winPeCommands.Add(@"
                <RunSynchronousCommand wcm:action="add">
                    <Order>$order</Order>
                    <Path>reg.exe add "HKLM\SYSTEM\Setup\LabConfig" /v BypassCPUCheck /t REG_DWORD /d 1 /f</Path>
                </RunSynchronousCommand>
"@)
    $order++
}

if ($config.Bypasses.BypassStorageCheck) {
    $winPeCommands.Add(@"
                <RunSynchronousCommand wcm:action="add">
                    <Order>$order</Order>
                    <Path>reg.exe add "HKLM\SYSTEM\Setup\LabConfig" /v BypassStorageCheck /t REG_DWORD /d 1 /f</Path>
                </RunSynchronousCommand>
"@)
    $order++
}

# Build Specialize commands
# Note: ComputerName (POS + random digits) is applied in SetupComplete.ps1 via Rename-Computer
# rather than in specialize RunSynchronous, because:
# 1) Microsoft-Windows-Deployment RunSynchronousCommand <Path> has a strict 259-char MAX_PATH schema limit.
# 2) Modifying ActiveComputerName in the registry during specialize desynchronizes the SAM domain name
#    before oobeSystem creates LocalAccounts, causing Windows Setup to abort with an unexpected error.
$specializeCommands = New-Object System.Collections.Generic.List[string]
$specOrder = 1

if ($config.Bypasses.BypassMicrosoftAccount) {
    $specializeCommands.Add(@"
                <RunSynchronousCommand wcm:action="add">
                    <Order>$specOrder</Order>
                    <Path>reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" /v BypassNRO /t REG_DWORD /d 1 /f</Path>
                </RunSynchronousCommand>
"@)
    $specOrder++
}

if ($config.Bypasses.DisableBitLockerAutoEncryption) {
    $specializeCommands.Add(@"
                <RunSynchronousCommand wcm:action="add">
                    <Order>$specOrder</Order>
                    <Path>reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\BitLocker" /v PreventDeviceEncryption /t REG_DWORD /d 1 /f</Path>
                </RunSynchronousCommand>
"@)
    $specOrder++
}

if ($config.Debloat.DisableTelemetryAndAds) {
    $specializeCommands.Add(@"
                <RunSynchronousCommand wcm:action="add">
                    <Order>$specOrder</Order>
                    <Path>reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Communications" /v ConfigureChatAutoInstall /t REG_DWORD /d 0 /f</Path>
                </RunSynchronousCommand>
"@)
    $specOrder++
    $specializeCommands.Add(@"
                <RunSynchronousCommand wcm:action="add">
                    <Order>$specOrder</Order>
                    <Path>reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent" /v DisableWindowsConsumerFeatures /t REG_DWORD /d 1 /f</Path>
                </RunSynchronousCommand>
"@)
    $specOrder++
}

# Optional Unattended Local Account block
$userAccountsXml = ""
if ($config.UserAccount.Mode -eq "UnattendedAccount" -and -not [string]::IsNullOrWhiteSpace($config.UserAccount.DefaultUsername)) {
    $uName = [System.Security.SecurityElement]::Escape($config.UserAccount.DefaultUsername)
    $uPass = [System.Security.SecurityElement]::Escape($config.UserAccount.DefaultPassword)
    $autoCount = [int]$config.UserAccount.AutoLogonCount
    $userAccountsXml = @"
            <UserAccounts>
                <LocalAccounts>
                    <LocalAccount wcm:action="add">
                        <Password>
                            <Value>$uPass</Value>
                            <PlainText>true</PlainText>
                        </Password>
                        <Description>Primary Local Administrator</Description>
                        <DisplayName>$uName</DisplayName>
                        <Group>Administrators</Group>
                        <Name>$uName</Name>
                    </LocalAccount>
                </LocalAccounts>
            </UserAccounts>
            <AutoLogon>
                <Password>
                    <Value>$uPass</Value>
                    <PlainText>true</PlainText>
                </Password>
                <Enabled>true</Enabled>
                <LogonCount>$autoCount</LogonCount>
                <Username>$uName</Username>
            </AutoLogon>
"@
}

$manufacturer = [System.Security.SecurityElement]::Escape($config.Branding.Manufacturer)
$model        = [System.Security.SecurityElement]::Escape($config.Branding.Model)
$timeZone     = [System.Security.SecurityElement]::Escape($config.Regional.TimeZone)
$inputLocale  = [System.Security.SecurityElement]::Escape($config.Regional.InputLocale)
$systemLocale = [System.Security.SecurityElement]::Escape($config.Regional.SystemLocale)
$uiLanguage   = [System.Security.SecurityElement]::Escape($config.Regional.FallbackUILanguage)

# Windows Setup (Microsoft-Windows-International-Core) rejects supplemental CLDR locales
# whose legacy LCID is 0x1000 (4096 / LOCALE_CUSTOM_UNSPECIFIED, such as en-CY) during oobeSystem
# with 0x80070057 (E_INVALIDARG). Use SystemLocale (en-US) in unattend.xml and apply en-CY
# via offline registry + Set-Culture in FirstLogon.ps1.
$rawUserLocale = $config.Regional.UserLocale
try {
    $ci = [System.Globalization.CultureInfo]::GetCultureInfo($rawUserLocale)
    if ($ci.LCID -eq 4096) {
        $rawUserLocale = $config.Regional.SystemLocale
    }
} catch {
    $rawUserLocale = $config.Regional.SystemLocale
}
$userLocale = [System.Security.SecurityElement]::Escape($rawUserLocale)

$xmlContent = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <!-- ================================================================= -->
    <!-- PASS 1: windowsPE (Hardware Check Bypasses & Setup Initialization) -->
    <!-- ================================================================= -->
    <settings pass="windowsPE">
$winPeIntlXml
        <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <RunSynchronous>
$($winPeCommands -join "`r`n")
            </RunSynchronous>
            <UserData>
                <ProductKey>
                    <WillShowUI>OnError</WillShowUI>
                </ProductKey>
                <AcceptEula>true</AcceptEula>
            </UserData>
        </component>
    </settings>

    <!-- ================================================================= -->
    <!-- PASS 4: specialize (OEM Branding, TimeZone, BypassNRO, Policies)  -->
    <!-- ================================================================= -->
    <settings pass="specialize">
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <OEMInformation>
                <Manufacturer>$manufacturer</Manufacturer>
                <Model>$model</Model>
            </OEMInformation>
            <RegisteredOrganization>$manufacturer</RegisteredOrganization>
            <TimeZone>$timeZone</TimeZone>
        </component>
        <component name="Microsoft-Windows-Deployment" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <RunSynchronous>
$($specializeCommands -join "`r`n")
            </RunSynchronous>
        </component>
    </settings>

    <!-- ================================================================= -->
    <!-- PASS 7: oobeSystem (Regional/Keyboard, Local Account, FirstLogon) -->
    <!-- ================================================================= -->
    <settings pass="oobeSystem">
        <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <InputLocale>$inputLocale</InputLocale>
            <SystemLocale>$systemLocale</SystemLocale>
            <UILanguage>$uiLanguage</UILanguage>
            <UserLocale>$userLocale</UserLocale>
        </component>
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <OOBE>
                <HideEULAPage>true</HideEULAPage>
                <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
                <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
                <HideWirelessSetupInOOBE>false</HideWirelessSetupInOOBE>
                <ProtectYourPC>3</ProtectYourPC>
            </OOBE>
$userAccountsXml
            <FirstLogonCommands>
                <SynchronousCommand wcm:action="add">
                    <Order>1</Order>
                    <Description>Run TinyWin 11 FirstLogon Application &amp; Customization Installer</Description>
                    <CommandLine>powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\TinyWin\Scripts\FirstLogon.ps1"</CommandLine>
                </SynchronousCommand>
            </FirstLogonCommands>
        </component>
    </settings>
</unattend>
"@

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($OutputPath, $xmlContent, $utf8NoBom)
Write-Host "[+] Generated autounattend.xml at: $OutputPath" -ForegroundColor Green
