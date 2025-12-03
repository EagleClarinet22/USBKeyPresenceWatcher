# YubiKey Presence Lock for Windows
![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)
![PowerShell 5.1](https://img.shields.io/badge/PowerShell-5.1-blue)

Automatically lock your Windows session when your YubiKey (or *any* chosen USB device) is removed - and keep the system locked until that device is reinserted.

This project includes:

- A PowerShell presence watcher
- Toast notifications via BurntToast (optional)
- A Windows Scheduled Task to start the watcher automatically
- Event Viewer logging (with file fallback)
- A fully interactive **installer** that detects your USB devices and lets you choose which one to monitor
- A matching **uninstaller** to cleanly remove the scheduled task
- A self-elevating install/uninstall flow (prompts for admin if needed)

> ⚠️ This script must run using **Windows PowerShell 5.1** (the built-in Windows PowerShell).
> PowerShell 7+ (pwsh.exe) is **not supported** for toast notifications, PnP enumeration, or hidden scheduled task windows.


### BurntToast Install Links
[BurntToast - GitHub](https://github.com/Windos/BurntToast)

[BurntToast - PSGallery](https://www.powershellgallery.com/packages/BurntToast/1.1.0)

---

## ✨ Features

### 🔐 Presence-based security  
Your workstation locks itself automatically when your selected USB device disappears - and keeps the system locked until the device returns.

### 🔁 Persistent lock enforcement  
If unlocked manually while your device is missing, the watcher re-locks the workstation instantly.

### 🔔 Toast notifications  
Optional (BurntToast module):

- Monitoring started
- Device removed
- Device reinserted

### 🧱 Hub-resilience  
Prevents false locks caused by USB hub power blips.  
(Default: requires “2 consecutive misses” before locking.)

### 🗂 Automatic Event Viewer logging  
All activity is logged under:
- Log: **Application**
- Source: **YubiKeyPresenceWatcher**

### 🧩 Smart installer workflow  
The installer:

- Detects all USB devices containing a VID/PID
- Lets you select the YubiKey (or any desired USB device)
- Extracts the correct `VID_XXXX&PID_YYYY`
- Updates only the *installed* script (never your repo version)
- Hardens the install directory ACLs
- Creates the EventLog source
- Generates a runtime task XML file:  
  - `Template-YubiKeyPresenceLock.xml` → `Task-YubiKeyPresenceLock.xml`
- Registers the Scheduled Task

Your repo stays clean - only the generated XML is ignored using `.gitignore`.

### 🔒 Secure installation directory  
The installer assigns FullControl to:

- The current user
- SYSTEM
- Administrators

All others are removed.

---

# 🚀 Installation

## 1. Clone or download the project

```powershell
git clone https://github.com/<your-username>/<your-repo>.git
cd <your-repo>
```

Or download and extract the ZIP.

---

## 2. (Recommended) Allow local scripts to run

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

---

## 3. Run the installer in Windows PowerShell (as Administrator)

> Note: The installer will auto-elevate (UAC prompt) if required.> You may run it normally from Windows PowerShell and it will handle elevation automatically.

If desired: Start key → Windows Powershell → Run as Administrator


```powershell
.\Install-USBKeyPresenceWatcher.ps1
```

To see options:

```powershell
.\Install-USBKeyPresenceWatcher.ps1 -Help
```

Common flags:

```powershell
# Change install directory
# defaults to C:\Scripts\USBKeyPresenceWatcher-Install
.\Install-USBKeyPresenceWatcher.ps1 -InstallDir 'C:\Scripts\USBKey'

# Force replace existing files & scheduled task
.\Install-USBKeyPresenceWatcher.ps1 -Force

# Skip device picker and supply a known VID/PID
.\Install-USBKeyPresenceWatcher.ps1 -YubiPrefix 'VID_1050&PID_0407'

# Output DEBUG-Task-Resolved.xml for troubleshooting
.\Install-USBKeyPresenceWatcher.ps1 -DebugXml

# Preview what would be installed (no changes made)
.\Install-USBKeyPresenceWatcher.ps1 -WhatIf
```

### What gets installed

The installer copies the following files to your install directory:

- `USBKeyPresenceLock.ps1` - The main watcher script
- `Template-USBKeyPresenceLock.xml` - Task scheduler template (used to generate the runtime XML)
- `Uninstall-USBKeyPresenceWatcher.ps1` - Uninstall script (for clean removal)
- `lock_toast_64.png` - Icon for toast notifications
- `LICENSE` - MIT license
- `NOTICE` - Attribution notice
- `README.md` - This documentation
- `Task-USBKeyPresenceLock.xml` - Generated at runtime (user and SID-specific)

---

## 4. Choose your USB device

The installer lists every detected USB device containing a VID/PID, for example:

```
[0] YubiKey OTP+FIDO+CCID
     USB\VID_1050&PID_0407\...

[1] USB Receiver
     USB\VID_046D&PID_C534\...
```

Type the number shown, or press:

- `M` - manually enter a VID/PID such as `VID_1050&PID_0407`

The installer then:

- Copies files into the install folder  
- Patches the installed script with your VID/PID  
- Hardens ACLs  
- Creates the EventLog source  
- Generates `Task-YubiKeyPresenceLock.xml`  
- Registers the scheduled task  

The `Template-YubiKeyPresenceLock.xml` file in your repo **is never modified**.

---

# 🔧 Configuration

## Change which device is monitored  
Re-run the installer:

```powershell
.\Install-YubiKeyPresenceWatcher.ps1 -Force
```

This regenerates:

- The patched installed script  
- The resolved task XML  
- The scheduled task  

---

## Hub-resilience tuning  
In the **installed** script (not the repo copy):

```powershell
$missingThreshold = 2
```

Higher values (e.g., 3–4) improve stability on noisy USB hubs.

---

# ❓ FAQ

### Do I need my VID/PID?  
No - the installer detects options automatically.

### Does this replace login authentication?  
No - this only **locks** your session based on device presence.

### Does this work with Windows Hello PIN?  
Yes. It enforces presence *after* login.

### Do I need BurntToast?  
No - toast notifications are optional.

### Why Windows PowerShell instead of PowerShell 7+?  
Scheduled tasks using hidden windows + BurntToast + PnpDevice require Windows PowerShell 5.1.

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

### Presence lock not triggering  
Check Event Viewer:

```
Windows Logs → Application → Source: YubiKeyPresenceWatcher
```

You should see entries such as:

- YubiKey missing
- Countdown in progress
- Locking workstation

---

### Scheduled Task fails to register  
Common causes:

- Elevation denied (UAC prompt declined)
- Modified/corrupt XML
- Execution policy blocking script

Re-run with:

```powershell
.\Install-YubiKeyPresenceWatcher.ps1 -Force
```

---

# 🧹 Uninstallation

## Recommended: Use the uninstaller script

The uninstall script is included in your install directory:

```powershell
C:\Scripts\USBKeyPresenceWatcher-Install\Uninstall-USBKeyPresenceWatcher.ps1
```

Or from the repo:

```powershell
.\Uninstall-USBKeyPresenceWatcher.ps1
```

For options:

```powershell
.\Uninstall-USBKeyPresenceWatcher.ps1 -Help
```

This will automatically:

- Auto-elevate itself if needed  
- Stop the running task  
- Delete the scheduled task  
- **Remove all files in the installation directory**
- **Remove the installation directory itself**

If you used a custom task name:

```powershell
.\Uninstall-USBKeyPresenceWatcher.ps1 -TaskName "My Custom Task"
```

To preview what would be removed without making changes:

```powershell
.\Uninstall-USBKeyPresenceWatcher.ps1 -WhatIf
```

---

## Manual uninstall (advanced)

```powershell
Unregister-ScheduledTask -TaskName "USB Key Presence Watcher" -Confirm:$false
```

Delete the install directory (default):

```
C:\Scripts\USBKeyPresenceWatcher-Install
```

(Optional) Remove the EventLog source:

```powershell
Remove-EventLog -Source USBKeyPresenceWatcher
```

---

# 🤝 Contributing

Pull requests are welcome.  
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
