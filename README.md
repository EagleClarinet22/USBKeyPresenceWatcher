# USB Key Presence Lock for Windows

![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)
![PowerShell 5.1](https://img.shields.io/badge/PowerShell-5.1-blue)
![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6)
![Automation](https://img.shields.io/badge/Scheduled%20Task-Automated-green)
![BurntToast](https://img.shields.io/badge/Toast%20Notifications-BurntToast-orange)
![Version](https://img.shields.io/github/v/tag/EagleClarinet22/USBKeyPresenceWatcher?label=version)
![CI](https://github.com/EagleClarinet22/USBKeyPresenceWatcher/actions/workflows/ci-validation.yml/badge.svg)

Automatically lock your Windows session when your selected **USB device** (security key, token, or any USB hardware you choose) is removed — and keep the system locked until that device is reinserted.

This project includes:

- A PowerShell presence watcher
- Toast notifications via BurntToast (optional)
- A Windows Scheduled Task to start the watcher automatically
- Event Viewer logging (with file fallback)
- A fully interactive **installer** that detects your USB devices
- A matching **uninstaller**
- A clean, self-elevating installation workflow
- **GitHub Actions pipelines** validating XML, linting PowerShell, and generating releases
- **Issue templates + Discussions** for structured reporting and community support

> ⚠️ This script must run using **Windows PowerShell 5.1** (the built-in Windows PowerShell).  
> PowerShell 7+ (pwsh.exe) is **not supported** for hidden scheduled-task execution, PnP APIs, or BurntToast.

---

## ✨ Features

### 🔐 Presence-based security

Locks your workstation automatically when your selected USB device disappears — and keeps it locked until the device returns.

### 🔁 Persistent lock enforcement

If the system is manually unlocked while the USB device is missing, the watcher immediately locks it again.

### 🔔 Toast notifications (optional)

Requires BurntToast. Indicates:

- Monitoring started
- Device removed
- Device reinserted

### 🧱 Hub-resilience

Prevents false positives from USB hub glitches (default: **2 consecutive misses** required to lock).

### 🗂 Automatic Event Viewer logging

Log: **Application**  
Source: **USBKeyPresenceWatcher**

### 🧩 Smart installer workflow

The installer:

- Detects all USB devices with VID/PID
- Lets you choose the correct USB device or token
- Patches the installed script with your VID/PID
- Hardens directory ACLs
- Creates the EventLog source
- Generates runtime task XML:

```
Template-USBKeyPresenceLock.xml → Task-USBKeyPresenceLock.xml
```

### 🔒 Secure installation directory

The installer grants FullControl to:

- Current user
- SYSTEM
- Administrators

All others are removed.

---

# 📁 Repository Structure

<details>
<summary><strong>Click here to view repo structure</strong></summary>

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
    ├── workflows/
    │     auto-hotfix.yml
    │     auto-nightly.yml
    │     release.yml
    │     validate-powershell.yml
    │     validate-xml.yml
    │     ci-validation.yml
    │
    └── ISSUE_TEMPLATE/
          improvement-roadmap.yml
          bug.yml
          feature.yml
          refactor.yml
          performance.yml
          documentation.yml
          workflow-failure.yml
          security.yml
          ux.yml
          config.yml
```

</details>

---

# ⚙ How It Works Internally

### 1. **Task Scheduler Startup**

The installer registers a task that runs at:

- User logon
- Session unlock

The task executes:

```
wscript.exe Launch-USBKeyPresenceWatcher.vbs
```

The VBS wrapper silently launches:

```
powershell.exe -WindowStyle Hidden -File USBKeyPresenceLock.ps1
```

This ensures **fully hidden execution**.

---

### 2. **USB Device Detection**

Once per second:

```powershell
Get-PnpDevice -PresentOnly | Where-Object InstanceId -like "*VID_####&PID_####*"
```

- Missing device → increment counter
- Present device → reset counter
- After N misses → lock workstation

---

### 3. **Locking Logic**

```powershell
rundll32.exe user32.dll,LockWorkStation
```

Optional heartbeat logs help diagnose issues.

---

### 4. **Single Instance Control**

A mutex prevents duplicate watchers:

```
USBKeyPresenceWatcher_<USERNAME>
```

---

### 5. **Event Logging + Toast Notifications**

Logs go to Event Viewer or a fallback local log file.  
Toast notifications appear if BurntToast is installed.

---

### 6. **Uninstallation**

The uninstaller:

- Terminates watcher instances
- Removes the scheduled task
- Deletes the installation directory
- Supports `-WhatIf`

Ensures complete cleanup.

---

# 🔧 Core Scripts

### `Install-USBKeyPresenceWatcher.ps1`

Handles:

- Selecting USB device
- Patching watcher with VID/PID
- Hardening ACLs
- Generating task XML
- Registering the task

---

### `Uninstall-USBKeyPresenceWatcher.ps1`

Handles:

- Killing watcher processes
- Removing scheduled task
- Cleaning directories
- Supporting dry runs with `-WhatIf`

---

### `USBKeyPresenceLock.ps1`

The core watcher:

- Polls for device
- Enforces lock-on-missing
- Logs events
- Sends notifications
- Prevents multiple instances

---

### `Launch-USBKeyPresenceWatcher.vbs`

Ensures the watcher runs:

- Hidden
- Under correct session
- Without console windows

---

### `Template-USBKeyPresenceLock.xml`

Defines triggers, actions, permissions, and runtime environment.

---

# 🤖 GitHub Workflows

- **validate-powershell.yml** — PSScriptAnalyzer checks
- **validate-xml.yml** — XML structure + encoding checks
- **release.yml** — Automated release generation
- **auto-hotfix.yml** — Auto hotfix creation based on commit volume *(disabled — manual run only)*
- **auto-nightly.yml** — Daily builds *(disabled — manual run only)*
- **ci-validation.yml** — Repository-wide validation

---

# 🚀 Installation

### 1. Download or clone

```powershell
git clone https://github.com/EagleClarinet22/USBKeyPresenceWatcher.git
cd USBKeyPresenceWatcher
```

### 2. Enable script execution

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

### 3. Run the installer

```powershell
.\Install-USBKeyPresenceWatcher.ps1
```

### 4. Select your USB device

Installer will list all detectable USB devices and let you choose one.

---

# 🔧 Configuration

### Re-select USB device

```powershell
.\Install-USBKeyPresenceWatcher.ps1 -Force
```

### Adjust hub-resilience threshold

```powershell
$missingThreshold = 2
```

---

# ❓ FAQ

<details>
<summary><strong>Expand FAQ</strong></summary>

### Do I need VID/PID?

No — the installer detects everything.

### Does this replace authentication?

No — this adds presence-based locking only.

### Does this work with Windows Hello?

Yes.

### Why Windows PowerShell 5.1?

Required for PnP APIs, BurntToast, and hidden scheduled-task execution.

</details>

---

# 🛠 Troubleshooting

### No toast notifications?

Install BurntToast:

```powershell
Install-Module BurntToast -Scope CurrentUser
```

Ensure:

- Task runs as logged-in user
- "Run only when user is logged on" is enabled

---

# 🧹 Uninstallation

```powershell
.\Uninstall-USBKeyPresenceWatcher.ps1
```

Supports:

- Instance cleanup
- Task removal
- Directory deletion
- `-WhatIf`

---

# 🤝 Contributing

Contributions are welcome!

Use structured issue templates for:

- Bug reports
- Feature requests
- Workflow failures
- UX improvements
- Documentation updates

For general questions or support, start a Discussion:  
https://github.com/EagleClarinet22/USBKeyPresenceWatcher/discussions

---

# 📜 License

MIT License. Attribution appreciated but not required.

---

Happy locking! 🔐

![GitHub Card](https://githubcard.com/EagleClarinet22.svg)
