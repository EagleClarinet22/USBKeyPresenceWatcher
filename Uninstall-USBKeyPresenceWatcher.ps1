# SPDX-License-Identifier: MIT
# Copyright (c) 2025 Connor Anderson

[CmdletBinding()]
param(
    [string]$TaskName = "USB Key Presence Watcher",
    [switch]$WhatIf,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

# Display WhatIf banner if enabled
if ($WhatIf) {
    Write-Host "[Simulation Mode] -WhatIf is enabled. No system changes will be made." -ForegroundColor Yellow
}

# Helper: unified ShouldProcess emulator
# PSScriptAnalyzer: Disable=PSUseShouldProcessForStateChangingCmdlets
function ShouldPerform {
    param(
        [string]$Target,
        [string]$Action
    )

    if ($WhatIf -or $WhatIfPreference) {
        Write-Host "WhatIf: $Action on $Target" -ForegroundColor Yellow
        return $false
    }

    return $true
}
# PSScriptAnalyzer: Enable=PSUseShouldProcessForStateChangingCmdlets

function Test-AdminElevation {
    $current = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($current)

    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        return
    }

    Write-Warning "Not running elevated. Opening PowerShell session with Administrator privileges..."

    $psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

    $argList = @("-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"")

    if ($TaskName) { $argList += @("-TaskName", "`"$TaskName`"") }
    if ($WhatIf) { $argList += "-WhatIf" }
    if ($Help) { $argList += "-Help" }

    Start-Process -FilePath $psExe -Verb RunAs -ArgumentList $argList
    exit
}

function Remove-WatcherTask {
    $oldEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    try {
        $null = schtasks.exe /query /tn "$TaskName" 2>$null
        $taskExists = ($LASTEXITCODE -eq 0)
    }
    finally {
        $ErrorActionPreference = $oldEAP
    }

    if (-not $taskExists) {
        Write-Warning "Scheduled task '$TaskName' does not exist. It may have been manually removed. Skipping task removal."
        return
    }

    Write-Host "Attempting to stop task '$TaskName' (if running)..." -ForegroundColor Yellow
    $null = schtasks.exe /end /tn "$TaskName" 2>$null

    Write-Host "Deleting task '$TaskName'..." -ForegroundColor Yellow
    $null = schtasks.exe /delete /tn "$TaskName" /f 2>$null

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to delete scheduled task '$TaskName'. Exit code: $LASTEXITCODE"
    }

    Write-Host "Scheduled task '$TaskName' removed successfully." -ForegroundColor Green
}

# Handle -Help
if ($Help) {
    Write-Host "Uninstall-USBKeyPresenceWatcher.ps1" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Stops and removes the USB Key Presence Watcher scheduled task."
    Write-Host ""
    Write-Host "Parameters:"
    Write-Host "  -TaskName <name>   Name of the scheduled task to remove"
    Write-Host "                     (default: 'USB Key Presence Watcher')."
    Write-Host "  -WhatIf            Simulate the deletion without making any changes."
    Write-Host "  -Help              Show this help text and exit."
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Yellow
    Write-Host "  .\Uninstall-USBKeyPresenceWatcher.ps1"
    Write-Host "  .\Uninstall-USBKeyPresenceWatcher.ps1 -TaskName 'Custom Task Name'"
    Write-Host ""
    return
}

Test-AdminElevation

# ----------------------------------------------------------
# MAIN UNINSTALL PROCESS (now properly wrapped in try/catch)
# ----------------------------------------------------------

try {
    Write-Host "Uninstalling scheduled task '$TaskName'..." -ForegroundColor Cyan

    # Determine install directory
    $InstallDir = Split-Path -Parent $PSCommandPath
    Write-Host "Stopping running watcher processes..." -ForegroundColor Yellow

    # Full paths to match against
    $watcherScript = Join-Path $InstallDir "USBKeyPresenceLock.ps1"
    $vbsLauncher = Join-Path $InstallDir "Launch-USBKeyWatcher.vbs"

    # Normalize escaped patterns for regex
    $escapedWatcher = [regex]::Escape($watcherScript)
    $escapedVbs = [regex]::Escape($vbsLauncher)

    # --- Kill powershell.exe instances running the watcher script ---
    try {
        $psList = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -ieq "powershell.exe" -and
            $_.CommandLine -match $escapedWatcher
        }

        foreach ($proc in $psList) {
            Write-Host "Stopping watcher PowerShell instance (PID $($proc.ProcessId))..." -ForegroundColor DarkYellow
            Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-Warning "Could not enumerate PowerShell processes by CIM: $($_.Exception.Message)"
    }

    # --- Kill wscript.exe instances running our VBS wrapper ---
    try {
        $wsList = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -ieq "wscript.exe" -and
            $_.CommandLine -match $escapedVbs
        }

        foreach ($proc in $wsList) {
            Write-Host "Stopping watcher VBScript host (PID $($proc.ProcessId))..." -ForegroundColor DarkYellow
            Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-Warning "Could not enumerate wscript processes: $($_.Exception.Message)"
    }

    Write-Host "Watcher processes stopped." -ForegroundColor Green
    
    # Step 2: Remove scheduled task
    Remove-WatcherTask

    # Remove VBS launcher if present
    $vbsPath = Join-Path $InstallDir "Launch-USBKeyWatcher.vbs"
    if (Test-Path $vbsPath) {
        Remove-Item $vbsPath -Force -ErrorAction SilentlyContinue
    }

    # Step 3: Remove installation directory and contents
    Write-Host "Cleaning up installation directory: $InstallDir" -ForegroundColor Yellow

    if (ShouldPerform("Installation directory '$InstallDir'", "Remove")) {

        # Remove files inside directory
        Get-ChildItem -Path $InstallDir -File | ForEach-Object {
            Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
        }

        # Remove directory itself
        Remove-Item -Path $InstallDir -Force -ErrorAction SilentlyContinue

        if (Test-Path $InstallDir) {
            Write-Warning "Could not fully remove directory '$InstallDir'. You may need to remove it manually."
        }
        else {
            Write-Host "Installation directory removed successfully." -ForegroundColor Green
        }
    }
}
catch {
    $msg = @"
FAILED TO COMPLETE UNINSTALLATION
--------------------------------
$($_.Exception.Message)

ORIGIN:
$($_.InvocationInfo.PositionMessage)

STACK TRACE:
$($_.ScriptStackTrace)
"@
    Write-Error $msg
}

# Pause if running in direct ConsoleHost
if ($Host.Name -eq "ConsoleHost") {
    Write-Host ""
    Read-Host "Press Enter to exit..."
}
