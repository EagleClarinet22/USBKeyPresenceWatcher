# SPDX-License-Identifier: MIT
# Copyright (c) 2025 Connor Anderson (EagleClarinet22)

[CmdletBinding()]
param(
    [string]$InstallDir = "C:\Scripts\USBKeyPresenceWatcher-Install",
    [string]$TaskName   = "USBKey Presence Watcher",
    [string]$YubiPrefix,
    [switch]$Force,
    [switch]$DebugXml,
    [switch]$WhatIf,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

# Display WhatIf banner if enabled
if ($WhatIf) {
    Write-Host "[Simulation Mode] -WhatIf is enabled. No system changes will be made." -ForegroundColor Yellow
}

# Helper: unified ShouldProcess emulator for safe state-changing operations
# PSScriptAnalyzer: Disable=PSUseShouldProcessForStateChangingCmdlets
function ShouldPerform {
    param(
        [string]$Target,
        [string]$Action
    )

    # Emulate WhatIf behavior: if script-level -WhatIf or builtin WhatIfPreference is set,
    # print a simulation line and return $false (do not perform).
    if ($WhatIf -or $WhatIfPreference) {
        Write-Host "WhatIf: $Action on $Target" -ForegroundColor Yellow
        return $false
    }

    return $true
}
# PSScriptAnalyzer: Enable=PSUseShouldProcessForStateChangingCmdlets

# ---------- Validate running as admin ----------
function Test-AdminElevation {
    # Check if already admin
    $current = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($current)

    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        return
    }

    Write-Warning "Not running elevated. Opening PowerShell session with Administrator privileges..."

    $psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

    # Build argument list using actual bound variables
    $argList = @("-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"")

    if ($InstallDir) { $argList += @("-InstallDir", "`"$InstallDir`"") }
    if ($TaskName)   { $argList += @("-TaskName", "`"$TaskName`"") }
    if ($YubiPrefix) { $argList += @("-YubiPrefix", "`"$YubiPrefix`"") }
    if ($Force)      { $argList += "-Force" }
    if ($DebugXml)   { $argList += "-DebugXml" }
    if ($WhatIf)     { $argList += "-WhatIf" }
    if ($Help)       { $argList += "-Help" }

    Start-Process -FilePath $psExe -Verb RunAs -ArgumentList $argList

    exit
}


# ---------- Help handler (can be shown without admin) ----------
if ($Help) {
    Write-Host "Install-USBKeyPresenceWatcher.ps1" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Installs the USB Key Presence Watcher:"
    Write-Host " - Copies the script and icon to an install folder"
    Write-Host " - Prompts for (or uses) a YubiKey/USB VID/PID prefix"
    Write-Host " - Patches the installed script to use that VID/PID"
    Write-Host " - Hardens ACLs on the install folder"
    Write-Host " - Creates the EventLog source (if possible)"
    Write-Host " - Generates Task-USBKeyPresenceLock.xml from Template-USBKeyPresenceLock.xml"
    Write-Host " - Registers a Scheduled Task from the generated Task XML"
    Write-Host ""
    Write-Host "Parameters:"
    Write-Host "  -InstallDir <path>      Target install folder (default: C:\Scripts\USBKey)"
    Write-Host "  -TaskName <name>        Scheduled Task name (default: 'USB Key Presence Watcher')"
    Write-Host "  -YubiPrefix <VID/PID>   Optional. Skip device selection and use this prefix directly."
    Write-Host "                          Example: -YubiPrefix 'VID_1050&PID_0407'"
    Write-Host "  -Force                  Overwrite existing files and re-register the task if present."
    Write-Host "  -DebugXml               Write DEBUG-Task-Resolved.xml with the resolved XML."
    Write-Host "  -WhatIf                 Simulate operations without making any changes."
    Write-Host "  -Help                   Show this help text and exit."
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Yellow
    Write-Host "  .\\Install-USBKeyPresenceWatcher.ps1"
    Write-Host "  .\\Install-USBKeyPresenceWatcher.ps1 -InstallDir 'C:\\Scripts\\USBKey' -Force"
    Write-Host "  .\\Install-USBKeyPresenceWatcher.ps1 -YubiPrefix 'VID_1050&PID_0407'"
    Write-Host "  .\\Install-USBKeyPresenceWatcher.ps1 -DebugXml"
    Write-Host ""
    return
}

Test-AdminElevation

Write-Host "Installing USB Key Presence Watcher to: $InstallDir" -ForegroundColor Cyan

# ---------- Resolve source directory (where this installer lives) ----------
$SourceDir = Split-Path -Parent $PSCommandPath
$ResolvedInstallDir = Resolve-Path $InstallDir -ErrorAction SilentlyContinue

if ($ResolvedInstallDir -and ($SourceDir -eq $ResolvedInstallDir)) {
    throw "ERROR: Installer cannot run from the same directory it installs into. 
    Move the installer out of '$InstallDir' or choose a different -InstallDir."
}

# Files expected in the repo/source directory
$scriptFile          = "USBKeyPresenceLock.ps1"
$iconFile            = "lock_toast_64.png"
$templateTaskXmlFile = "Template-USBKeyPresenceLock.xml"

foreach ($f in @($scriptFile, $iconFile, $templateTaskXmlFile)) {
    $fullPath = Join-Path $SourceDir $f
    if (-not (Test-Path $fullPath)) {
        throw "Required file '$f' not found in source directory: $SourceDir"
    }
}

# ---------- Helper: ask user which device to monitor & derive VID/PID ----------
function Get-YubiPrefixFromUser {
    Write-Host ""
    Write-Host "Detecting USB/PnP devices to choose from..." -ForegroundColor Cyan

    $yubiPrefix = $null

    # Try to import PnpDevice to enumerate hardware
    $pnpModuleLoaded = $false
    try {
        Import-Module PnpDevice -ErrorAction Stop
        $pnpModuleLoaded = $true
    } catch {
        Write-Warning "Could not import PnpDevice module. You will need to enter the VID_XXXX&PID_YYYY prefix manually."
    }

    if ($pnpModuleLoaded) {
        try {
            $devices = Get-PnpDevice -PresentOnly |
                Where-Object { $_.InstanceId -match 'VID_[0-9A-Fa-f]{4}&PID_[0-9A-Fa-f]{4}' } |
                Sort-Object FriendlyName, InstanceId

            if ($devices -and $devices.Count -gt 0) {
                Write-Host ""
                Write-Host "Select the USB device to monitor for presence (likely your USB security key):" -ForegroundColor Yellow
                Write-Host ""

                for ($i = 0; $i -lt $devices.Count; $i++) {
                    $dev   = $devices[$i]
                    $label = if ($dev.FriendlyName) { $dev.FriendlyName } else { $dev.Name }

                    Write-Host ("[{0}] {1}" -f $i, $label)
                    Write-Host ("     {0}" -f $dev.InstanceId)
                    Write-Host ""
                }

                while ($true) {
                    $choice = Read-Host "Enter the number of the device to use, or 'M' to enter VID/PID manually"

                    if ($choice -match '^[Mm]$') {
                        break  # go to manual entry
                    }

                    if ($choice -match '^\d+$') {
                        $idx = [int]$choice
                        if ($idx -ge 0 -and $idx -lt $devices.Count) {
                            $selected = $devices[$idx]
                            $match = [regex]::Match($selected.InstanceId, 'VID_[0-9A-Fa-f]{4}&PID_[0-9A-Fa-f]{4}')
                            if ($match.Success) {
                                $yubiPrefix = $match.Value.ToUpper()
                                Write-Host "Selected device: $($selected.FriendlyName)" -ForegroundColor Green
                                Write-Host "Using VID/PID prefix: $yubiPrefix" -ForegroundColor Green
                                break
                            } else {
                                Write-Warning "Could not extract VID/PID from that device. Try another index or use manual mode."
                            }
                        } else {
                            Write-Warning "Invalid index. Try again."
                        }
                    } else {
                        Write-Warning "Invalid input. Enter an index number or 'M'."
                    }
                }
            } else {
                Write-Warning "No devices with VID_XXXX&PID_YYYY found. Falling back to manual entry."
            }
        } catch {
            Write-Warning "Error while listing devices: $($_.Exception.Message). Falling back to manual entry."
        }
    }

    # Manual entry fallback or chosen 'M'
        while (-not $yubiPrefix) {
            Write-Host ""
            Write-Host "Enter the VID/PID prefix to monitor (for example: VID_1050&PID_0407)" -ForegroundColor Yellow
            $userInput = Read-Host "VID/PID prefix"
    
            if ($userInput -match '^VID_[0-9A-Fa-f]{4}&PID_[0-9A-Fa-f]{4}$') {
                $yubiPrefix = $userInput.ToUpper()
            } else {
                Write-Warning "Invalid format. Expected something like: VID_1050&PID_0407"
            }
        }

    return $yubiPrefix
}

# ---------- Resolve YubiPrefix (parameter or interactive) ----------
if ($YubiPrefix) {
    if ($YubiPrefix -notmatch '^VID_[0-9A-Fa-f]{4}&PID_[0-9A-Fa-f]{4}$') {
        throw "Provided -YubiPrefix '$YubiPrefix' is invalid. Expected format like: VID_1050&PID_0407"
    }
    $selectedYubiPrefix = $YubiPrefix.ToUpper()
    Write-Host ""
    Write-Host "Using provided YubiPrefix: $selectedYubiPrefix" -ForegroundColor Green
} else {
    $selectedYubiPrefix = Get-YubiPrefixFromUser
    Write-Host ""
    Write-Host "Final selected USB Key/device prefix: $selectedYubiPrefix" -ForegroundColor Green
}

# ---------- Create / validate install directory ----------
if (-not (Test-Path $InstallDir)) {
    Write-Host "Creating directory $InstallDir"
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
} elseif (-not $Force) {
    Write-Host "Directory $InstallDir already exists. Existing files may be overwritten."
}

# ---------- Copy files into install directory ----------
Write-Host "Copying files to $InstallDir..."
if (ShouldPerform("Files in $InstallDir", "Copy")) {
    Copy-Item (Join-Path $SourceDir $scriptFile)          -Destination $InstallDir -Force
    Copy-Item (Join-Path $SourceDir $iconFile)            -Destination $InstallDir -Force
    Copy-Item (Join-Path $SourceDir $templateTaskXmlFile) -Destination $InstallDir -Force
}

# ---------- Patch ONLY the installed script with the selected VID/PID ----------
$scriptDestPath = Join-Path $InstallDir $scriptFile

# Read script only in non-WhatIf mode; in WhatIf mode we skip the actual file ops
if (-not ($WhatIf -or $WhatIfPreference)) {
    $scriptContent  = Get-Content $scriptDestPath -Raw

    # We expect a line like: $yubiPrefix = "VID_1050&PID_0407"
    $pattern = '(\$yubiPrefix\s*=\s*")[^"]*(")'

    if ($scriptContent -match $pattern) {
        $scriptContent = $scriptContent -replace $pattern, "`$1$selectedYubiPrefix`$2"
        Set-Content -Path $scriptDestPath -Value $scriptContent -Encoding UTF8
        Write-Host "Updated installed script with USB Key/device prefix: $selectedYubiPrefix" -ForegroundColor Green
    } else {
        Write-Warning "Could not find yubiPrefix assignment line to patch in the installed script. Check USBKeyPresenceLock.ps1 format."
    }
} else {
    Write-Host "WhatIf: Patch script with USB Key/device prefix: $selectedYubiPrefix" -ForegroundColor Yellow
}

# ---------- Harden ACLs on the install directory ----------
Write-Host "Hardening ACLs on $InstallDir..."

if (ShouldPerform("Directory ACL on $InstallDir", "Set")) {
    $acl = New-Object System.Security.AccessControl.DirectorySecurity
    $inheritFlags      = [System.Security.AccessControl.InheritanceFlags]"ContainerInherit, ObjectInherit"
    $propagationFlags  = [System.Security.AccessControl.PropagationFlags]::None
    $accessControlType = [System.Security.AccessControl.AccessControlType]::Allow
    $rights            = [System.Security.AccessControl.FileSystemRights]::FullControl

    # Use DOMAIN\Username form for safety (DOMAIN may be machine name)
    $accountName = "$env:USERDOMAIN\$env:USERNAME"
    $currentUser = New-Object System.Security.Principal.NTAccount($accountName)
    $admins      = New-Object System.Security.Principal.NTAccount("Administrators")
    $system      = New-Object System.Security.Principal.NTAccount("SYSTEM")

    foreach ($id in @($currentUser, $admins, $system)) {
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $id, $rights, $inheritFlags, $propagationFlags, $accessControlType
        )
        $acl.AddAccessRule($rule) | Out-Null
    }

    Set-Acl -Path $InstallDir -AclObject $acl
    Write-Host "ACLs set: $($currentUser.Value), Administrators, and SYSTEM have FullControl." -ForegroundColor Green
}

# ---------- Ensure EventLog source exists ----------
$eventSource  = "USBKeyPresenceWatcher"
$eventLogName = "Application"

# PSScriptAnalyzer: Disable=PSUseShouldProcessForStateChangingCmdlets
try {
    if (-not [System.Diagnostics.EventLog]::SourceExists($eventSource)) {
        Write-Host "Creating EventLog source '$eventSource' in '$eventLogName' (admin required)..." -ForegroundColor Yellow
        if (ShouldPerform("EventLog source '$eventSource'", "Create in $eventLogName")) {
            New-EventLog -LogName $eventLogName -Source $eventSource
        }
    }
} catch {
    Write-Warning "Could not create EventLog source '$eventSource': $($_.Exception.Message)"
}
# PSScriptAnalyzer: Enable=PSUseShouldProcessForStateChangingCmdlets

# ---------- Build resolved task XML from template ----------
$templateXmlPath = Join-Path $InstallDir $templateTaskXmlFile
$xmlContent      = Get-Content $templateXmlPath -Raw

# Values to plug into the XML
$scriptPath  = $scriptDestPath      # full path to USBKeyPresenceLock.ps1 in the install dir
$workDir     = $InstallDir
$accountName = "$env:USERDOMAIN\$env:USERNAME"

# Resolve SID for the current user
try {
    $userNt  = New-Object System.Security.Principal.NTAccount($accountName)
    $userSid = $userNt.Translate([System.Security.Principal.SecurityIdentifier]).Value
} catch {
    throw "Failed to resolve SID for '$accountName': $($_.Exception.Message)"
}

# Escape values for XML safety
$escapedScriptPath = [System.Security.SecurityElement]::Escape($scriptPath)
$escapedWorkDir    = [System.Security.SecurityElement]::Escape($workDir)
$escapedUser       = [System.Security.SecurityElement]::Escape($accountName)
$escapedUserSid    = [System.Security.SecurityElement]::Escape($userSid)

# Replace placeholders in the template
$xmlResolved = $xmlContent `
    -replace "__SCRIPT_PATH__",  $escapedScriptPath `
    -replace "__WORK_DIR__",     $escapedWorkDir `
    -replace "__USERNAME__",     $escapedUser `
    -replace "__USERNAME_SID__", $escapedUserSid

# Write the resolved XML to a persistent task XML in the install dir
$taskXmlResolvedPath = Join-Path $InstallDir "Task-USBKeyPresenceLock.xml"
if (ShouldPerform("Task XML file '$taskXmlResolvedPath'", "Write")) {
    Set-Content -Path $taskXmlResolvedPath -Value $xmlResolved -Encoding Unicode
    Write-Host "Generated task XML: $taskXmlResolvedPath" -ForegroundColor Green
}

# Optional DEBUG XML dump
if ($DebugXml) {
    $debugXmlPath = Join-Path $InstallDir "DEBUG-Task-USBKeyPresenceLock.xml"
    if (ShouldPerform("DEBUG task XML file '$debugXmlPath'", "Write")) {
        Set-Content -Path $debugXmlPath -Value $xmlResolved -Encoding Unicode
        Write-Host "DEBUG: Wrote resolved XML to $debugXmlPath" -ForegroundColor Yellow
    }
}

# ---------- Register Scheduled Task using SCHTASKS.EXE ----------
Write-Host "Registering scheduled task '$TaskName'..."

# PSScriptAnalyzer: Disable=PSUseShouldProcessForStateChangingCmdlets
# Remove existing task if present
try {
    schtasks.exe /query /tn "$TaskName" > $null 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Existing task '$TaskName' found. Removing..."
        if (ShouldPerform("Scheduled task '$TaskName'", "Delete existing")) {
            schtasks.exe /delete /tn "$TaskName" /f > $null
        }
    }
} catch {}

Write-Host "Importing task from generated XML..."
if (ShouldPerform("Scheduled task '$TaskName'", "Create from XML")) {
    schtasks.exe /create /tn "$TaskName" /xml "$taskXmlResolvedPath" /f | Out-Null

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to register scheduled task. schtasks.exe exited with code $LASTEXITCODE."
    }

    Write-Host "Scheduled task '$TaskName' registered successfully." -ForegroundColor Green
}
# PSScriptAnalyzer: Enable=PSUseShouldProcessForStateChangingCmdlets

Write-Host ""
Write-Host "Installation complete. Log off and back on to test the watcher." -ForegroundColor Green

if ($Host.Name -eq "ConsoleHost") {
    Write-Host ""
    Read-Host "Press Enter to exit..."
}
