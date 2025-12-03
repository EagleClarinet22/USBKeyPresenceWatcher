# C:\Scripts\YubiKeyPresenceWatcher\YubiKeyPresenceLock.ps1
# YubiKey presence watcher:
# - Watches for a YubiKey (VID_1050&PID_0407) via PnP.
# - Locks the workstation if it's missing for N consecutive checks.
# - Optional toast notifications via BurntToast.
# - Checks for key presence immediately on user logon.
# - Logs primarily to Event Viewer (Application) with file fallback.
# - Ensures only a single instance per user runs at any time.

# ---------- CONFIG ----------
# Match this substring in InstanceId (good for USB\VID_1050&PID_0407\...)
$yubiPrefix = "VID_1050&PID_0407"

# How many consecutive "missing" checks before we lock (hub resilience)
$missingThreshold = 2       # 2 checks * 1 sec = ~2 seconds

# Figure out where this script lives
$ScriptRoot = Split-Path -Parent $PSCommandPath

# Log file (fallback if EventLog not available)
$logPath = Join-Path $env:LOCALAPPDATA "YubiKeyPresenceLock.log"

# Icon for toast notifications (optional)
$iconPath = Join-Path $ScriptRoot "lock_toast_64.png"

# Event Log config
$eventLogName = "Application"
$eventSource  = "YubiKeyPresenceWatcher"
# ----------------------------

$ErrorActionPreference = "Stop"

# ---------- EVENT LOG INITIALIZATION ----------
# Best-effort: ensure the event source exists. This may require admin the first time.
try {
    if (-not [System.Diagnostics.EventLog]::SourceExists($eventSource)) {
        New-EventLog -LogName $eventLogName -Source $eventSource
    }
} catch {
    # If this fails (e.g. no admin), we just fall back to file logging in Write-Log.
}

# ---------- HELPER FUNCTIONS ----------
function Write-Log {
    param([string]$Message)

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "$timestamp`t$Message"

    try {
        if ([System.Diagnostics.EventLog]::SourceExists($eventSource)) {
            Write-EventLog -LogName $eventLogName `
                           -Source  $eventSource `
                           -EntryType Information `
                           -EventId 1000 `
                           -Message $Message
        } else {
            # Fallback to file if source isn't available
            Add-Content -Path $logPath -Value $line
        }
    } catch {
        # Last resort: try to write to file log
        try {
            Add-Content -Path $logPath -Value $line
        } catch {
            # If this also fails, we silently give up.
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
$mutexName = "YubiKeyPresenceWatcher_$($env:USERNAME)"
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
                if (Test-Path $iconPath) {
                    New-BurntToastNotification -Text $Title, $Message -AppLogo $iconPath | Out-Null
                } else {
                    New-BurntToastNotification -Text $Title, $Message | Out-Null
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
    for ($i = 1; $i -le 10; $i++) {
        if (-not (Test-YubiPresent)) {
            Write-Log "YubiKey not present on logon attempt. Locking workstation."
            rundll32.exe user32.dll,LockWorkStation
            Start-Sleep -Seconds 1
        } else {
            Write-Log "YubiKey present at logon."
            break
        }
    }

    $wasPresent   = Test-YubiPresent
    $missingCount = 0

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
                    Show-Toast "YubiKey Detected" "YubiKey is present again."
                }
                $missingCount = 0
                $wasPresent   = $true
            }
            else {
                # First time missing
                if ($wasPresent) {
                    Write-Log "YubiKey missing. Beginning hub-resilience countdown."
                    Show-Toast "YubiKey Missing" "Waiting briefly in case of USB glitch..."
                    $wasPresent   = $false
                    $missingCount = 0
                }

                $missingCount++
                Write-Log "YubiKey still missing. Consecutive missing count: $missingCount"

                # Lock after threshold
                if ($missingCount -ge $missingThreshold) {
                    Write-Log "YubiKey missing for $missingCount checks. Locking workstation."
                    Show-Toast "YubiKey Missing" "YubiKey absent. Locking workstation."
                    rundll32.exe user32.dll,LockWorkStation

                    # Keep the counter from growing forever, but stay "armed"
                    $missingCount = $missingThreshold
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
        try { $mutex.ReleaseMutex() | Out-Null } catch {}
        $mutex.Dispose()
    }
}
