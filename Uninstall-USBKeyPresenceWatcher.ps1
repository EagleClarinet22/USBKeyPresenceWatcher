# SPDX-License-Identifier: MIT
# Copyright (c) 2025 Connor Anderson (EagleClarinet22)

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

    if ($TaskName)   { $argList += @("-TaskName", "`"$TaskName`"") }
    if ($WhatIf)     { $argList += "-WhatIf" }
    if ($Help)       { $argList += "-Help" }

    Start-Process -FilePath $psExe -Verb RunAs -ArgumentList $argList

    exit
}

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

Write-Host "Uninstalling scheduled task '$TaskName'..." -ForegroundColor Cyan

# Determine the install directory from this script's location
$InstallDir = Split-Path -Parent $PSCommandPath

# PSScriptAnalyzer: Disable=PSUseShouldProcessForStateChangingCmdlets
try {
    # Check if the task exists
    schtasks.exe /query /tn "$TaskName" > $null 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Scheduled task '$TaskName' was not found. Nothing to remove."
        return
    }

    Write-Host "Attempting to stop task '$TaskName' (if running)..." -ForegroundColor Yellow
    if (ShouldPerform("Scheduled task '$TaskName'", "Stop if running")) {
        schtasks.exe /end /tn "$TaskName" > $null 2>&1
    }

    Write-Host "Deleting task '$TaskName'..." -ForegroundColor Yellow
    if (ShouldPerform("Scheduled task '$TaskName'", "Delete")) {
        schtasks.exe /delete /tn "$TaskName" /f > $null

        if ($LASTEXITCODE -ne 0) {
            throw "schtasks.exe /delete returned exit code $LASTEXITCODE"
        }

        Write-Host "Scheduled task '$TaskName' removed successfully." -ForegroundColor Green
    }
    
    # Clean up the install directory
    Write-Host "Cleaning up installation directory: $InstallDir" -ForegroundColor Yellow
    if (ShouldPerform("Installation directory '$InstallDir'", "Remove")) {
        # Remove all files in the install directory (including this uninstall script)
        Get-ChildItem -Path $InstallDir -File | ForEach-Object {
            Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
        }
        
        # Remove the directory itself
        Remove-Item -Path $InstallDir -Force -ErrorAction SilentlyContinue
        
        if (Test-Path $InstallDir) {
            Write-Warning "Could not fully remove directory '$InstallDir'. You may need to remove it manually."
        } else {
            Write-Host "Installation directory removed successfully." -ForegroundColor Green
        }
    }
}
catch {
    Write-Error "Failed to complete uninstallation: $($_.Exception.Message)"
}
# PSScriptAnalyzer: Enable=PSUseShouldProcessForStateChangingCmdlets

if ($Host.Name -eq "ConsoleHost") {
    Write-Host ""
    Read-Host "Press Enter to exit..."
}
