# YubiKey Presence Lock for Windows

Automatically lock your Windows session when your YubiKey (or *any* chosen USB device) is removed — and keep the system locked until that device is reinserted.

This project includes:

- A PowerShell presence watcher
- Toast notifications via [BurntToast] (optional)
- A Windows Scheduled Task to start the watcher automatically
- Event Viewer logging (with file fallback)
- A fully interactive **installer** that detects your USB devices and lets you choose which one to monitor

> ⚠️ The script must run using **Windows PowerShell 5.1** (built into Windows).  
PowerShell 7+ (pwsh) is **not supported** for this task.

[BurntToast]: https://github.com/Windos/BurntToast

---

## ✨ Features

### 🔐 Presence-based security  
Your workstation locks automatically when your chosen USB device disappears and remains locked until the device is reinserted.

### 🔁 Persistent lock enforcement  
If you try to unlock the PC while the device is missing, the watcher instantly relocks your session.

### 🔔 Toast notifications  
Optional (BurntToast module):

- Monitoring started  
- Device removed  
- Device reinserted  

### 🧱 Hub-resilience  
The watcher ignores short USB glitches and only locks after “N” consecutive absence checks.

### 🗂 Automatic Event Viewer logging  
Every action is logged under the `Application` log, source `YubiKeyPresenceWatcher`.

### 🧩 One-time configuration  
The installer:

- Detects connected USB devices
- Lets you **select** your YubiKey (or any device)
- Automatically extracts the correct `VID_XXXX&PID_YYYY`
- Updates ONLY the installed script with that value  
- Leaves your repo version untouched

### 🔒 Secure installation folder  
The installer creates (or uses) `C:\Scripts\YubiKey` and tightens permissions to:

- The installing user
- SYSTEM
- Administrators

---

## 🚀 Installation

## 1. Clone or download the repository

```powershell
git clone https://github.com/<your-username>/<your-repo>.git
cd <your-repo>
```

Or download the ZIP and extract it.

---

## 2. Run PowerShell as Administrator (first install only)

Right-click **Windows PowerShell** → **Run as administrator**

Then:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

This allows local scripts to run.

---

## 3. Run the installer

From the repo directory:

```powershell
.\Install-YubiKeyPresenceWatcher.ps1
```

You will be shown a list of detected USB devices containing a `VID_XXXX&PID_YYYY`.

Example:

```
[0] YubiKey OTP+FIDO+CCID
     USB\VID_1050&PID_0407\...

[1] USB Input Device
     USB\VID_046D&PID_C534\...
```

Type:

- The number corresponding to your YubiKey, **or**
- `M` to manually enter a VID/PID prefix (e.g., `VID_1050&PID_0407`)

The installer will then:

- Copy the script files into `C:\Scripts\YubiKey`
- Patch the installed script with your selected VID/PID  
- Harden folder permissions  
- Create the EventLog source (if allowed)  
- Register the Scheduled Task using the XML template  
- Substitute:
  - `__SCRIPT_PATH__`
  - `__WORK_DIR__`
  - `__USERNAME__`
  - `__USERNAME_SID__`

Your repo files remain unchanged.

---

## 4. Log off and log back in

You should see:

- “YubiKey Watcher — Monitoring started” (toast)
- System locks a moment after you remove the selected USB device

---

# 🔧 Configuration

## Changing which device to monitor  
Since the watcher script is patched during install, you must **re-run the installer** if you want to choose a different device:

```powershell
.\Install-YubiKeyPresenceWatcher.ps1 -Force
```

This overwrites the installed script and re-registers the Scheduled Task.

---

## Hub-resilience threshold  
In the script (installed copy):

```powershell
$missingThreshold = 2
```

This means:

- 1 check per second
- Locks after 2 seconds of absence

Increase for flaky USB hubs (e.g., `3` or `4`).

---

## Task Scheduler Configuration

The installed Scheduled Task:

- Runs **only when the user is logged on**
- Uses `powershell.exe -WindowStyle Hidden`
- Starts at:
  - Logon
  - Workstation unlock (optional in your template)
- Runs with **highest privileges**

---

# ❓ FAQ

### Do I need to know my YubiKey’s VID/PID?
No — the installer detects and lists all USB devices automatically.

### Does this replace password login?
No. This is **presence-based session locking**, not authentication replacement.

### Does this work if I log in with Windows Hello PIN?
Yes — the watcher enforces presence **after login**, not before.

### Do I need BurntToast?  
No. If the module cannot be imported, the script runs normally without notifications.

### Can I use PowerShell 7 instead of Windows PowerShell 5.1?
No. The following features require Windows PowerShell 5.1:

- BurntToast
- PnpDevice module
- UWP/WinRT toast infrastructure
- Task Scheduler hidden-window mode

### Does the watcher ask for the device every time it runs?
**Never.**  
The *installer* asks once.  
The *runtime script* uses the patched value.

---

# 🛠 Troubleshooting

### No notification toasts
- Install BurntToast:

  ```powershell
  Install-Module BurntToast -Scope CurrentUser
  ```

- Make sure the Task is running as **your user**  
- Ensure "Run only when user is logged on" is enabled

### The script is not locking the PC
Check Event Viewer → **Application log → Source: YubiKeyPresenceWatcher**

You should see messages like:

- "YubiKey missing. Beginning hub-resilience countdown."
- "YubiKey still missing. Consecutive missing count: X"
- "Locking workstation."

If not:

- Ensure the scheduled task is running
- Ensure VID/PID matches your device:

  ```powershell
  Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -like "*VID_*" }
  ```

### Scheduled Task fails to register  
Typical causes:

- You did not run the installer as Administrator  
- Your XML file has been modified accidentally  
- Windows blocked execution of the installer (right-click → Unblock)

---

# 🧹 Uninstallation

1. Delete the scheduled task:

   ```powershell
   Unregister-ScheduledTask -TaskName "YubiKey Presence Watcher" -Confirm:$false
   ```

2. Delete the install folder:

   ```
   C:\Scripts\YubiKey
   ```

3. (Optional) Remove the EventLog source:

   ```powershell
   Remove-EventLog -Source YubiKeyPresenceWatcher
   ```

---

# 🤝 Contributing

- Pull requests welcome  
- Issues can be reported via GitHub  
- Please include reproduction steps and your OS version

---

# 📜 License

MIT License — see `LICENSE` file.

---

Happy locking! 🔐
