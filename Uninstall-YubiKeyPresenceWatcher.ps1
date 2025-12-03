[CmdletBinding()]
param(
    [string]$TaskName = "YubiKey Presence Watcher",
    [switch]$Help
)

$ErrorActionPreference = "Stop"

function Test-RunningAsAdmin {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal       = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    $isAdmin         = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if ($isAdmin) {
        return
    }

    Write-Warning "This script is not running with elevated (Administrator) privileges."
    Write-Warning "Attempting to relaunch with elevation..."

    if (-not $PSCommandPath) {
        throw "Cannot self-elevate because PSCommandPath is not available. Please rerun this script in an elevated PowerShell session."
    }

    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")

    foreach ($key in $PSBoundParameters.Keys) {
        if ($key -eq 'Help') { continue }

        $value = $PSBoundParameters[$key]

        if ($value -is [System.Management.Automation.SwitchParameter]) {
            if ($value.IsPresent) {
                $argList += "-$key"
            }
        } else {
            $escaped = $value.ToString().Replace('"', '\"')
            $argList += "-$key"
            $argList += "`"$escaped`""
        }
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName  = "powershell.exe"
    $psi.Arguments = $argList -join ' '
    $psi.Verb      = "runas"

    try {
        [Diagnostics.Process]::Start($psi) | Out-Null
        Write-Host "Relaunched elevated. Exiting non-elevated instance..." -ForegroundColor Yellow
        exit
    } catch {
        throw "Elevation failed: $($_.Exception.Message). Please rerun this script as Administrator."
    }
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

Test-RunningAsAdmin

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
