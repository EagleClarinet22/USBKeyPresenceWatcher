# YubiKey Presence Lock for Windows

![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)
![PowerShell 5.1](https://img.shields.io/badge/PowerShell-5.1-blue)
![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6)
![Automation](https://img.shields.io/badge/Scheduled%20Task-Automated-green)
![BurntToast](https://img.shields.io/badge/Toast%20Notifications-BurntToast-orange)
![Version](https://img.shields.io/github/v/tag/EagleClarinet22/USBKeyPresenceWatcher?label=version)
![CI](https://github.com/EagleClarinet22/USBKeyPresenceWatcher/actions/workflows/ci-validation.yml/badge.svg)


Automatically lock your Windows session when your YubiKey (or _any_ chosen USB device) is removed — and keep the system locked until that device is reinserted.

This project includes:

- A PowerShell presence watcher
- Toast notifications via BurntToast (optional)
- A Windows Scheduled Task to start the watcher automatically
- Event Viewer logging (with file fallback)
- A fully interactive **installer** that detects your USB devices
- A matching **uninstaller**
- A clean, self-elevating installation workflow

> ⚠️ This script must run using **Windows PowerShell 5.1** (the built-in Windows PowerShell).  
> PowerShell 7+ (pwsh.exe) is **not supported** for hidden scheduled-task execution, PnP APIs, or BurntToast.

---

## ✨ Features

### 🔐 Presence-based security

Locks your workstation automatically when your selected USB device disappears — and keeps it locked until the device returns.

### 🔁 Persistent lock enforcement

If you manually unlock your workstation while the device is missing, the watcher immediately re-locks it.

### 🔔 Toast notifications

(Requires BurntToast)

- Monitoring started
- Device removed
- Device reinserted

### 🧱 Hub-resilience

Prevents false positives from USB hub glitches (default: **2 consecutive misses** required to lock).

### 🗂 Automatic Event Viewer logging

Log: **Application**  
Source: **YubiKeyPresenceWatcher**

### 🧩 Smart installer workflow

The installer:

- Detects all USB devices with VID/PID
- Lets you choose the correct YubiKey or token
- Patches the installed script with your VID/PID
- Hardens directory ACLs
- Creates the EventLog source
- Generates a runtime task XML:

```
Template-USBKeyPresenceLock.xml → Task-USBKeyPresenceLock.xml
```

Your repo stays clean — only runtime output is ignored.

### 🔒 Secure installation directory

Installer grants FullControl to:

- The current user
- SYSTEM
- Administrators

All others removed.

---

# 📁 Repository Structure

<details>
<summary><strong>Click here to view repo structure</strong></summary>

The **USBKeyPresenceWatcher** project consists of a PowerShell-based security watcher, a hidden-process launcher, an installer and uninstaller, and a Windows Task Scheduler template.

```
USBKeyPresenceWatcher/
│
│   Install-USBKeyPresenceWatcher.ps1
│   Uninstall-USBKeyPresenceWatcher.ps1
│   USBKeyPresenceLock.ps1
│   Launch-USBKeyPresenceWatcher.vbs
│   Template-USBKeyPresenceLock.xml
│   lock_toast_64.png
│
│   CHANGELOG.md
│   README.md
│   LICENSE
│   NOTICE
│
│   .editorconfig
│   .gitattributes
│   .gitignore
│   .prettierignore
│
└── .github/
    └── workflows/
            auto-hotfix.yml
            auto-nightly.yml
            release.yml
            validate-powershell.yml
            validate-xml.yml
```

</details>

---

# ⚙ How It Works Internally

This section provides a technical overview of the system for maintainers and advanced users.

### 1. **Task Scheduler Startup**

The installer registers a scheduled task configured to run:

- At user logon
- On session unlock

The task launches:

```
wscript.exe Launch-USBKeyPresenceWatcher.vbs
```

The VBS wrapper silently launches:

```
powershell.exe -WindowStyle Hidden -File USBKeyPresenceLock.ps1
```

Ensuring **no console window appears**.

---

### 2. **USB Device Detection**

The watcher polls the system once per second:

```powershell
Get-PnpDevice -PresentOnly | Where-Object InstanceId -like "*VID_1050&PID_0407*"
```

A missing device increments a counter.  
A present device resets it.

Only after **N consecutive misses** is the workstation locked.

---

### 3. **Locking Logic**

When the threshold is reached:

```powershell
rundll32.exe user32.dll,LockWorkStation
```

While locked, a heartbeat log entry is emitted periodically (disabled or adjustable).

---

### 4. **Single Instance Control**

A mutex prevents multiple simultaneous watchers:

```
USBKeyPresenceWatcher_<USERNAME>
```

This prevents duplicate tasks from triggering overlapping watchers.

---

### 5. **Event Logging + Toasts**

Logs are written to:

- **Event Viewer** (if source exists)
- Else to a local log file

Notifications are sent via BurntToast if installed.

---

### 6. **Uninstallation**

The uninstaller:

- Terminates running wscript.exe / powershell.exe watcher instances
- Removes the scheduled task
- Deletes the installation directory
- Supports `-WhatIf`

A full clean removal is guaranteed.

---

# 🔧 Core Scripts

### `Install-USBKeyPresenceWatcher.ps1`

Handles installation of the watcher system:

- Copies required files into the installation directory
- Applies ACL hardening
- Resolves placeholders in the XML template
- Registers or updates the Scheduled Task
- Supports debug XML generation

---

### `Uninstall-USBKeyPresenceWatcher.ps1`

Safely removes the watcher:

- Terminates running watcher instances (VBS/PowerShell)
- Removes the Scheduled Task
- Wipes the installation directory
- Supports `-WhatIf` testing

---

### `USBKeyPresenceLock.ps1`

The main watcher daemon responsible for:

- Detecting presence of the configured USB security key
- Locking the workstation when the device is removed
- Logging to Event Viewer or fall back log file
- Displaying toast notifications via BurntToast
- Ensuring only a single instance runs (mutex)

---

### `Launch-USBKeyPresenceWatcher.vbs`

A VBS launcher that:

- Runs the watcher script **fully hidden**
- Ensures execution occurs under the interactive user session
- Prevents PowerShell console windows from appearing

---

### `Template-USBKeyPresenceLock.xml`

Task Scheduler XML template containing:

- Script path
- Working directory
- User SID
- Run conditions

---

### `lock_toast_64.png`

Icon used in toast notifications via BurntToast.

---

## 📄 Project Metadata

### `CHANGELOG.md`

The version history of the project.  
Also used by GitHub Actions to generate release notes.

### `README.md`

User-facing documentation, setup instructions, and overview of the project.

### `LICENSE` / `NOTICE`

Legal files for distribution and attribution.

---

## ⚙ Configuration

### `.editorconfig`

Enforces consistent formatting and encoding:

- CRLF for PowerShell
- ANSI for VBS
- UTF-8 rules for other text files
- Prevents editors from breaking encoding-sensitive scripts

---

### `.gitattributes`

Defines how Git handles:

- Binary/text detection
- Line-ending normalization
- Encoding stability (especially for VBS)

---

### `.gitignore`

Specifies which local files and build artifacts should be excluded from version control.

### `.prettierignore`

Specifies which files Prettier must **not** format.

---

## 🤖 GitHub Workflows (`.github/workflows/`)

### `validate-powershell.yml`

Runs PSScriptAnalyzer to ensure correct PowerShell formatting and syntax.

### `validate-xml.yml`

Ensures task XML files remain valid and well-formed.

### `release.yml`

Automatically generates GitHub Releases from tagged versions, pulling notes from `CHANGELOG.md`.

### `auto-hotfix.yml`

Automates creation of hotfix releases based on commit activity.

### `auto-nightly.yml`

Builds nightly development releases.

---

# 🚀 Installation

## 1. Clone or download the project

```powershell
git clone https://github.com/<your-username>/<your-repo>.git
cd <your-repo>
```

---

## 2. (Recommended) Allow local scripts to run

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

---

## 3. Run the installer in Windows PowerShell (as Administrator)

> Note: The installer will auto-elevate (UAC prompt) if required. You may run it normally from Windows PowerShell and it will handle elevation automatically.

```powershell
.\Install-USBKeyPresenceWatcher.ps1
```

To see options:

```powershell
.\Install-USBKeyPresenceWatcher.ps1 -Help
```

---

## 4. Choose your USB device

The installer lists every detected USB device containing a VID/PID.

Then it:

- Copies files into the install folder
- Patches the installed script
- Hardens ACLs
- Creates the EventLog source
- Generates `Task-USBKeyPresenceLock.xml`
- Registers the scheduled task

---

# 🔧 Configuration

### Change which device is monitored

```powershell
.\Install-YubiKeyPresenceWatcher.ps1 -Force
```

---

### Hub-resilience tuning

In the installed script:

```powershell
$missingThreshold = 2
```

---

# ❓ FAQ

<details>
<summary><strong>Click to expand FAQ</strong></summary>

### Do I need my VID/PID?

No — the installer detects options automatically.

### Does this replace authentication?

No — it only **locks** based on device presence.

### Does this work with Windows Hello PIN?

Yes.

### Why Windows PowerShell instead of PowerShell 7+?

BurntToast, PnP APIs, and hidden scheduled task execution require PS 5.1.

</details>

---

# 🛠 Troubleshooting

### No toast notifications

Install BurntToast:

```powershell
Install-Module BurntToast -Scope CurrentUser
```

Ensure:

- Task runs as the logged-in user
- “Run only when user is logged on” is enabled

---

# 🧹 Uninstallation

### Recommended

```powershell
.\Uninstall-USBKeyPresenceWatcher.ps1
```

Supports:

- Auto-elevation
- Task removal
- Directory cleanup
- `-WhatIf`

---

# 🤝 Contributing

Pull requests are welcome!  
If reporting issues, please include:

- Windows version
- Device VID/PID
- Events from Event Viewer

---

## License

This project is licensed under the [MIT License](./LICENSE).

## Attribution

If you use this project, or substantial portions of its scripts, in your own
work, attribution to the original author is appreciated:

- Author: **EagleClarinet22 (Connor Anderson)**
- Please retain the [NOTICE](./NOTICE) file where practical.

Attribution is not required by the license, but it is encouraged.

---

Happy locking! 🔐

![GitHub Card](https://githubcard.com/EagleClarinet22.svg)
