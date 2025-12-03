# SPDX-License-Identifier: MIT
# Copyright (c) 2025 Connor Anderson (EagleClarinet22)

[CmdletBinding()]
param(
    [string]$TaskName = "YubiKey Presence Watcher",
    [switch]$Help
)

$ErrorActionPreference = "Stop"

function Test-AdminElevation {
    # Check if already elevated
    $current = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($current)

    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        return
    }

    Write-Warning "Not running as Administrator. Elevating..."

    # Explicit Windows PowerShell 5.1 path
    $psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

    # Capture exact command used to launch the script
    $invocation = $MyInvocation.Line
    if (-not $invocation) {
        throw "Unable to capture the invocation line. Do not run this script from ISE or through pwsh.exe."
    }

    # Relaunch elevated (no -NoExit)
    Start-Process -FilePath $psExe -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass", "-Command", $invocation

    # Stop the non-admin instance
    exit
}



if ($Help) {
    Write-Host "Uninstall-YubiKeyPresenceWatcher.ps1" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Stops and removes the YubiKey Presence Watcher scheduled task."
    Write-Host ""
    Write-Host "Parameters:"
    Write-Host "  -TaskName <name>   Name of the scheduled task to remove"
    Write-Host "                     (default: 'YubiKey Presence Watcher')."
    Write-Host "  -Help              Show this help text and exit."
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Yellow
    Write-Host "  .\Uninstall-YubiKeyPresenceWatcher.ps1"
    Write-Host "  .\Uninstall-YubiKeyPresenceWatcher.ps1 -TaskName 'Custom Task Name'"
    Write-Host ""
    return
}

Test-AdminElevation

Write-Host "Uninstalling scheduled task '$TaskName'..." -ForegroundColor Cyan

try {
    # Check if the task exists
    schtasks.exe /query /tn "$TaskName" > $null 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Scheduled task '$TaskName' was not found. Nothing to remove."
        return
    }

    Write-Host "Attempting to stop task '$TaskName' (if running)..." -ForegroundColor Yellow
    schtasks.exe /end /tn "$TaskName" > $null 2>&1

    Write-Host "Deleting task '$TaskName'..." -ForegroundColor Yellow
    schtasks.exe /delete /tn "$TaskName" /f > $null

    if ($LASTEXITCODE -ne 0) {
        throw "schtasks.exe /delete returned exit code $LASTEXITCODE"
    }

    Write-Host "Scheduled task '$TaskName' removed successfully." -ForegroundColor Green
}
catch {
    Write-Error "Failed to remove scheduled task '$TaskName': $($_.Exception.Message)"
}

if ($Host.Name -eq "ConsoleHost") {
    Write-Host ""
    Read-Host "Press Enter to exit..."
}
