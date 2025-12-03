# Changelog

All notable changes to USBKeyPresenceLock.ps1 are documented here.

## [1.0.1] - 2025-12-03

### Fixed
- **Repeated toast notifications and workstation locks** - Script was continuously re-locking and sending duplicate toast notifications after the security key was removed. Now locks only once and suppresses repeated actions until the key is reinserted.
- **Log spam** - Eliminated repeated "key missing" log entries while workstation is already locked.
- **Task Scheduler errors** - "The operator or administrator refused the request" errors were caused by non-interactive task execution attempting UI actions and admin-only operations. Fixed by implementing safe elevation checks and deferring EventLog creation to admin-only context.
- **PSScriptAnalyzer warnings** - Added suppression comments and error handling to satisfy code analysis rules.
- **Install/Uninstall scripts lacked testing capability** - No way to safely preview operations before executing. Both scripts now support `-WhatIf` simulation mode.

### Added
- **Locked-state tracking** - Introduced `$isLocked` boolean flag to prevent repeated lock/toast actions while already in locked state.
- **Periodic heartbeat logging** - Low-volume heartbeat log entries (no toasts) while workstation is locked. Configurable via `-lockedHeartbeatInterval` parameter (default 300 seconds).
- **-WhatIf simulation support** - Script now supports `-WhatIf` flag for safe, non-destructive testing. All system-modifying actions (locks, log writes, notifications, EventLog creation) are wrapped with `ShouldPerform` checks.
- **WhatIf simulation console echo** - Visible cyan heartbeat message printed to console during `-WhatIf` mode when heartbeat triggers, improving testing visibility.
- **Safe EventLog creation** - EventLog source creation now only occurs when script is running elevated. Non-elevated runs fallback to file-based logging without repeated permission errors.
- **Script-local log fallback** - When EventLog source is unavailable and script is non-elevated, logs are written to `USBKeyPresenceLock.log` in the script's directory instead of LocalAppData, ensuring non-elevated instances can still log.
- **Parameter for runtime control** - Added `-lockedHeartbeatInterval` parameter to override heartbeat frequency without editing the script.
- **Install script WhatIf mode** - Install script now supports `-WhatIf` parameter to preview all operations (file copies, ACL changes, EventLog source creation, task registration) without making changes.
- **Uninstall script WhatIf mode** - Uninstall script now supports `-WhatIf` parameter to preview task deletion without making changes.

### Changed
- **Logon enforcement loop** - Now locks workstation only once if security key is missing at logon, then breaks. Previously would repeatedly lock every loop iteration.
- **Missing counter logic** - Counter no longer increments beyond threshold while already locked, preventing redundant state transitions.
- **Error handling** - Empty catch blocks now include explanatory comments for PSScriptAnalyzer compliance.
- **Project file naming** - Renamed all files from "YubiKey" theme to "USBKey" theme for broader device support:
  - `YubiKeyPresenceLock.ps1` → `USBKeyPresenceLock.ps1`
  - `Install-YubiKeyPresenceWatcher.ps1` → `Install-USBKeyPresenceWatcher.ps1`
  - `Uninstall-YubiKeyPresenceWatcher.ps1` → `Uninstall-USBKeyPresenceWatcher.ps1`
  - `Template-YubiKeyPresenceLock.xml` → `Template-USBKeyPresenceLock.xml`
  - Event Log source: `YubiKeyPresenceWatcher` → `USBKeyPresenceWatcher`
  - Log files: `YubiKeyPresenceLock.log` → `USBKeyPresenceLock.log`

### Technical Details
- **ShouldPerform helper function** - Portable emulation of ShouldProcess that works with or without `$PSCmdlet` availability, allowing `-WhatIf` support without `[CmdletBinding]` parser issues.
- **Elevation detection** - Uses `Security.Principal.WindowsPrincipal` to safely check if running as Administrator.
- **Log file hierarchy** - Attempts Event Log → Script-local log → LocalAppData log, gracefully degrading if permissions prevent higher-priority options.

### Testing

Test the main watcher script in simulation mode without making any system changes:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "USBKeyPresenceLock.ps1" -WhatIf
```

Test with a custom heartbeat interval (e.g., 10 seconds for quick visibility):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "USBKeyPresenceLock.ps1" -WhatIf -lockedHeartbeatInterval 10
```

Test the Install script in simulation mode:

```powershell
.\Install-USBKeyPresenceWatcher.ps1 -WhatIf
```

Test the Uninstall script in simulation mode:

```powershell
.\Uninstall-USBKeyPresenceWatcher.ps1 -WhatIf
```

## Configuration

- `$yubiPrefix` - USB VID/PID substring to match (default: `VID_1050&PID_0407` for common USB security keys).
- `$missingThreshold` - Consecutive missing checks before lock (default: 2, ~2 seconds).
- `-lockedHeartbeatInterval` - Seconds between heartbeat logs while locked (default: 300). Pass `0` to disable.

## Notes for Deployment

### Task Scheduler Setup

When creating a scheduled task to run this script:

1. **General tab:**
   - Run as your interactive user account (not SYSTEM).
   - Select "Run only when user is logged on".
   - Do NOT check "Run with highest privileges" unless admin actions are required.

2. **Triggers tab:**
   - Set to "At log on" (for the user).

3. **Actions tab:**
   - Program: `powershell.exe`
   - Arguments: `-NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\USBKey\USBKeyPresenceLock.ps1"`

### EventLog Source Creation

If the script runs non-elevated, it will fallback to file logging. To enable Event Log logging, create the source once as Administrator:

```powershell
if (-not [System.Diagnostics.EventLog]::SourceExists('USBKeyPresenceWatcher')) {
  New-EventLog -LogName 'Application' -Source 'USBKeyPresenceWatcher'
}
```

After this one-time setup, all non-elevated instances will write to the Event Log without permission errors.
