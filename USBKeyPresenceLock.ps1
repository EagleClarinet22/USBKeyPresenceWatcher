# SPDX-License-Identifier: MIT
# Copyright (c) 2025 Connor Anderson (EagleClarinet22)

# YubiKey presence watcher:
# - Watches for a YubiKey (VID_1050&PID_0407) via PnP.
# - Locks the workstation if it's missing for N consecutive checks.
# - Optional toast notifications via BurntToast.
# - Checks for key presence immediately on user logon.
# - Logs primarily to Event Viewer (Application) with file fallback.
# - Ensures only a single instance per user runs at any time.

# ---------- CONFIG ----------
param(
    [switch]$WhatIf,
    [int]$lockedHeartbeatInterval = 300
)

# Helper: unified ShouldProcess emulator. If running as an advanced script/function
# with $PSCmdlet available, prefer its ShouldProcess so built-in -WhatIf/-Confirm
# works. Otherwise emulate WhatIf behavior via the script-level -WhatIf switch or
# the automatic $WhatIfPreference variable.
[void] # Removed CmdletBinding to avoid parser issues in some PowerShell hosts; using emulation instead.
# PSScriptAnalyzer: Disable=PSUseShouldProcessForStateChangingCmdlets
function ShouldPerform {
    param(
        [string]$Target,
        [string]$Action
    )

    # If we have a $PSCmdlet (advanced script), call its ShouldProcess
    if ($PSCmdlet -and $PSCmdlet -is [object] -and $PSCmdlet.ShouldProcess) {
        return $PSCmdlet.ShouldProcess($Target, $Action)
    }

    # Otherwise, emulate WhatIf: if script-level -WhatIf or the builtin WhatIfPreference
    # is set, print a simulation line and return $false (do not perform).
    if ($WhatIf -or $WhatIfPreference) {
        Write-Host "WhatIf: $Action on $Target" -ForegroundColor Yellow
        return $false
    }

    return $true
}
# PSScriptAnalyzer: Enable=PSUseShouldProcessForStateChangingCmdlets

if ($WhatIf -or $WhatIfPreference) {
    Write-Host "[Simulation Mode] -WhatIf is enabled. No system changes will be made." -ForegroundColor Yellow
}

# Match this substring in InstanceId (good for USB\VID_1050&PID_0407\...)
$yubiPrefix = "VID_1050&PID_0407"

# How many consecutive "missing" checks before we lock (hub resilience)
$missingThreshold = 2       # 2 checks * 1 sec = ~2 seconds

# When locked, write a low-volume heartbeat to the log every N seconds.
# Set to 0 to disable heartbeat logging. This value can be overridden via
# the script parameter `-lockedHeartbeatInterval`.

# Figure out where this script lives
$ScriptRoot = Split-Path -Parent $PSCommandPath

# Log file (fallback if EventLog not available)
$logPath = Join-Path $env:LOCALAPPDATA "USBKeyPresenceLock.log"

# Icon for toast notifications (optional)
$iconPath = Join-Path $ScriptRoot "lock_toast_64.png"

# Event Log config
$eventLogName = "Application"
$eventSource  = "USBKeyPresenceWatcher"
# ----------------------------

$ErrorActionPreference = "Stop"

# ---------- EVENT LOG INITIALIZATION ----------
# Best-effort: check whether the event source exists. Creating a new event source
# requires administrative privileges, so only create it automatically when the
# script is running elevated. If not elevated, the script will continue and use
# file-based logging until an admin creates the source once.

# Flag indicating whether the event source is available for Write-EventLog
$eventLogAvailable = $false

try {
    $eventLogAvailable = [System.Diagnostics.EventLog]::SourceExists($eventSource)
} catch {
    $eventLogAvailable = $false
}

# If the source doesn't exist, try to create it only if running elevated.
if (-not $eventLogAvailable) {
    try {
        $isElevated = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        $isElevated = $false
    }

    if ($isElevated) {
        try {
            if (ShouldPerform("EventLog source '$eventSource'", "Create source in $eventLogName")) {
                New-EventLog -LogName $eventLogName -Source $eventSource
                $eventLogAvailable = $true
            } else {
                # Simulation or denied - do not create
                $eventLogAvailable = $false
            }
        } catch {
            # If creation fails even when elevated, fall back to file logging.
            $eventLogAvailable = $false
        }
    } else {
        # Non-elevated: we do not attempt to create the source. Provide a
        # one-time instruction later (via Write-Log) so the admin can create it.
        $eventLogAvailable = $false
        # Prefer a log file in the script's directory for non-elevated runs so
        # that the watcher can still record startup errors and important events.
        try {
            $scriptLogPath = Join-Path $ScriptRoot "USBKeyPresenceLock.log"
            # Use the script-local log file instead of the per-user LocalAppData file
            $logPath = $scriptLogPath
            # Create directory/file if necessary and append an initial note
            $startupNote = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`tEventLog source '$eventSource' not available; using script-local log '$logPath'"
            if (ShouldPerform("LogFile '$logPath'", "Append startup note")) {
                Add-Content -Path $logPath -Value $startupNote -ErrorAction SilentlyContinue
            }
        } catch {
            # If we can't even write to the script dir, fall back to original LocalAppData path
            $logPath = Join-Path $env:LOCALAPPDATA "YubiKeyPresenceLock.log"
        }
    }
}

# ---------- HELPER FUNCTIONS ----------
function Write-Log {
    param([string]$Message)

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "$timestamp`t$Message"

    try {
        if ($eventLogAvailable) {
            if (ShouldPerform("EventLog '$eventLogName'", "Write event ($eventSource): $Message")) {
                Write-EventLog -LogName $eventLogName `
                               -Source  $eventSource `
                               -EntryType Information `
                               -EventId 1000 `
                               -Message $Message
            }
        } else {
            # Fallback to file if source isn't available
            if (ShouldPerform("LogFile '$logPath'", "Append message")) {
                Add-Content -Path $logPath -Value $line
            }
        }
    } catch {
        # Last resort: try to write to file log
        try {
            if (ShouldPerform("LogFile '$logPath'", "Append message (fallback)")) {
                Add-Content -Path $logPath -Value $line
            }
        } catch {
            # If this also fails, we silently give up.
            # (Cannot log here without risking infinite recursion)
        }
    }
}

function Test-YubiPresent {
    try {
        $dev = Get-PnpDevice -PresentOnly |
               Where-Object { $_.InstanceId -like "*$yubiPrefix*" }
        return [bool]$dev
    } catch {
        # Fail-safe: don't lock on errors
        return $true
    }
}

# ---------- SINGLE INSTANCE GUARD (MUTEX) ----------
# Prevent multiple instances per user (logon + unlock triggers, manual runs, etc.)
$mutexName = "USBKeyPresenceWatcher_$($env:USERNAME)"
$createdNew = $false
$mutex = $null

try {
    $mutex = New-Object System.Threading.Mutex($false, $mutexName, [ref]$createdNew)
    if (-not $createdNew) {
        Write-Log "Another instance of YubiKeyPresenceLock is already running. Exiting."
        return
    }
} catch {
    Write-Log "Failed to create/check mutex '$mutexName': $($_.Exception.Message). Continuing without single-instance guarantee."
}

try {
    # === Import PnpDevice ===
    try {
        Import-Module PnpDevice -ErrorAction Stop
    } catch {
        $msg = "PnpDevice module not available: $($_.Exception.Message)"
        Write-Log $msg
        return
    }

    # === Import BurntToast (once!) ===
    $script:UseBurntToast = $false
    try {
        Import-Module BurntToast -ErrorAction Stop
        $script:UseBurntToast = $true
        Write-Log "BurntToast imported successfully."
    } catch {
        Write-Log "BurntToast failed to import: $($_.Exception.Message)"
    }

    function Show-Toast {
        param(
            [string]$Title,
            [string]$Message
        )
        if ($script:UseBurntToast) {
            try {
                if (ShouldPerform("Notification", "Show toast: $Title - $Message")) {
                    if (Test-Path $iconPath) {
                        New-BurntToastNotification -Text $Title, $Message -AppLogo $iconPath | Out-Null
                    } else {
                        New-BurntToastNotification -Text $Title, $Message | Out-Null
                    }
                }
            } catch {
                Write-Log "BurntToast Show-Toast failed: $($_.Exception.Message)"
            }
        }
    }

    # ----------- Startup Logging ---------------
    Write-Log "=== YubiKey presence watcher started (prefix contains '$yubiPrefix', threshold = $missingThreshold) ==="
    Show-Toast "YubiKey Watcher" "Presence monitoring started."

    # ----------- LOGIN ENFORCEMENT: Require YubiKey ----------
    # If the key is missing at logon, lock once and proceed (don't spam locks).
    for ($i = 1; $i -le 10; $i++) {
        if (-not (Test-YubiPresent)) {
            Write-Log "YubiKey not present on logon attempt. Locking workstation."
            Show-Toast "YubiKey Missing" "YubiKey absent at logon. Locking workstation."
            if (ShouldPerform('Workstation','Lock')) {
                rundll32.exe user32.dll,LockWorkStation
            }
            # Lock once and break; the main watcher will continue monitoring.
            break
        } else {
            Write-Log "YubiKey present at logon."
            break
        }
    }

    $wasPresent   = Test-YubiPresent
    $missingCount = 0
    # Track whether we've already locked the workstation due to a missing key
    $isLocked = $false
    # Track last heartbeat time while locked
    $lastHeartbeat = Get-Date

    # ------------ Main loop: polls once per second --------------
    if ($wasPresent) {
        Write-Log "YubiKey present at startup."
    } else {
        Write-Log "YubiKey NOT present at startup."
    }

    while ($true) {
        try {
            $present = Test-YubiPresent

            if ($present) {
                # Reset counters when the key reappears
                if (-not $wasPresent) {
                    Write-Log "YubiKey reinserted."
                    # If we had previously locked, notify once that it's back
                    if ($isLocked) {
                        Show-Toast "YubiKey Detected" "YubiKey is present again."
                    }
                }
                $missingCount = 0
                $wasPresent   = $true
                # Reset locked state when key returns
                $isLocked = $false
            }
            else {
                # If we're already locked, suppress repeating missing logs/toasts
                # and emit a low-volume heartbeat occasionally.
                if ($isLocked) {
                    if ($lockedHeartbeatInterval -gt 0) {
                        $elapsed = (Get-Date) - $lastHeartbeat
                        if ($elapsed.TotalSeconds -ge $lockedHeartbeatInterval) {
                            Write-Log "Watcher heartbeat: YubiKey still missing and workstation locked."
                            # When running in simulation (-WhatIf), also echo a visible heartbeat line to the console
                            if ($WhatIf -or $WhatIfPreference) {
                                Write-Host "[Simulation Mode] Heartbeat: YubiKey still missing and workstation locked." -ForegroundColor Cyan
                            }
                            $lastHeartbeat = Get-Date
                        }
                    }
                    Start-Sleep -Seconds 1
                    continue
                }

                # First time missing
                if ($wasPresent) {
                    Write-Log "YubiKey missing. Beginning hub-resilience countdown."
                    Show-Toast "YubiKey Missing" "Waiting briefly in case of USB glitch..."
                    $wasPresent   = $false
                    # Start counting from 1 for the first missing check
                    $missingCount = 1
                    # Ensure we haven't already locked
                    $isLocked = $false
                    Write-Log "Starting missing counter at $missingCount"
                    Start-Sleep -Seconds 1
                    continue
                }
                # Only increment up to the threshold
                if ($missingCount -lt $missingThreshold) {
                    $missingCount++
                }
                if (-not $isLocked) {
                    Write-Log "YubiKey still missing. Consecutive missing count: $missingCount"
                }

                # Lock once when we reach the threshold. Don't repeat locks/toasts while still missing.
                if (($missingCount -ge $missingThreshold) -and (-not $isLocked)) {
                    Write-Log "YubiKey missing for $missingCount checks. Locking workstation."
                    Show-Toast "YubiKey Missing" "YubiKey absent. Locking workstation."
                    if (ShouldPerform('Workstation','Lock')) {
                        rundll32.exe user32.dll,LockWorkStation
                    }
                    $isLocked = $true
                    # small pause after locking to avoid immediate retriggering
                    Start-Sleep -Seconds 5
                }
            }

        } catch {
            Write-Log "Error in main loop: $($_.Exception.Message)"
            Start-Sleep -Seconds 5
        }

        Start-Sleep -Seconds 1
    }
}
finally {
    # Release mutex when script exits (if we acquired it)
    if ($mutex -and $createdNew) {
        try { $mutex.ReleaseMutex() | Out-Null } catch { <# Ignore mutex release errors #> }
        $mutex.Dispose()
    }
}

