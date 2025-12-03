[CmdletBinding()]
param(
    [string]$InstallDir = "C:\Scripts\YubiKey",
    [string]$TaskName   = "YubiKey Presence Watcher",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

Write-Host "Installing YubiKey Presence Watcher to: $InstallDir" -ForegroundColor Cyan

# Resolve source directory (where this installer lives)
$SourceDir = Split-Path -Parent $PSCommandPath

# Files expected in repo
$scriptFile   = "YubiKeyPresenceLock.ps1"
$iconFile     = "lock_toast_64.png"
$taskXmlFile  = "Task-YubiKeyPresenceLock.xml"

foreach ($f in @($scriptFile, $iconFile, $taskXmlFile)) {
    if (-not (Test-Path (Join-Path $SourceDir $f))) {
        throw "Required file '$f' not found in $SourceDir"
    }
}

# Create install directory
if (-not (Test-Path $InstallDir)) {
    Write-Host "Creating directory $InstallDir"
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
} elseif (-not $Force) {
    Write-Host "Directory $InstallDir already exists."
}

# Copy files
Write-Host "Copying files..."
Copy-Item (Join-Path $SourceDir $scriptFile)  -Destination $InstallDir -Force
Copy-Item (Join-Path $SourceDir $iconFile)    -Destination $InstallDir -Force
Copy-Item (Join-Path $SourceDir $taskXmlFile) -Destination $InstallDir -Force

# Hardening ACLs on the directory
Write-Host "Hardening ACLs on $InstallDir..."

$acl = New-Object System.Security.AccessControl.DirectorySecurity
$inheritFlags      = [System.Security.AccessControl.InheritanceFlags]"ContainerInherit, ObjectInherit"
$propagationFlags  = [System.Security.AccessControl.PropagationFlags]::None
$accessControlType = [System.Security.AccessControl.AccessControlType]::Allow
$rights            = [System.Security.AccessControl.FileSystemRights]::FullControl

$currentUser = New-Object System.Security.Principal.NTAccount("$env:USERDOMAIN\$env:USERNAME")
$admins      = New-Object System.Security.Principal.NTAccount("Administrators")
$system      = New-Object System.Security.Principal.NTAccount("SYSTEM")

foreach ($id in @($currentUser, $admins, $system)) {
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $id, $rights, $inheritFlags, $propagationFlags, $accessControlType
    )
    $acl.AddAccessRule($rule) | Out-Null
}

Set-Acl -Path $InstallDir -AclObject $acl
Write-Host "ACLs set: $($currentUser.Value), Administrators, SYSTEM have FullControl." -ForegroundColor Green

# Ensure EventLog source exists
$eventSource  = "YubiKeyPresenceWatcher"
$eventLogName = "Application"

try {
    if (-not [System.Diagnostics.EventLog]::SourceExists($eventSource)) {
        Write-Host "Creating EventLog source '$eventSource' (admin required)..."
        New-EventLog -LogName $eventLogName -Source $eventSource
    }
} catch {
    Write-Warning "Could not create EventLog source '$eventSource': $($_.Exception.Message)"
}

# ---- Register Scheduled Task from XML template ----
Write-Host "Registering scheduled task '$TaskName'..."

$scriptPath = Join-Path $InstallDir $scriptFile

# Resolve username + SID
$username = $env:USERNAME
$userSid  = (New-Object System.Security.Principal.NTAccount($username)).Translate([System.Security.Principal.SecurityIdentifier]).Value

# Load XML template
$xmlTemplate = Get-Content (Join-Path $InstallDir $taskXmlFile) -Raw

# Replacement with proper XML escaping
$xmlResolved = $xmlTemplate `
    -replace "__SCRIPT_PATH__", [System.Security.SecurityElement]::Escape($scriptPath) `
    -replace "__WORK_DIR__",    [System.Security.SecurityElement]::Escape($InstallDir) `
    -replace "__USERNAME__",    [System.Security.SecurityElement]::Escape($username) `
    -replace "__USERNAME_SID__", [System.Security.SecurityElement]::Escape($userSid)

# Delete any existing task first
try {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Write-Host "Existing task '$TaskName' found. Removing..."
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    }
} catch {}

# Register new task
Register-ScheduledTask -TaskName $TaskName -Xml $xmlResolved -User $username -RunLevel Highest | Out-Null

Write-Host "Scheduled task '$TaskName' registered successfully." -ForegroundColor Green

Write-Host "Installation complete." -ForegroundColor Green
