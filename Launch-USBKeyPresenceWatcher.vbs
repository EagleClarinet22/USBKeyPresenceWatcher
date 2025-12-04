Set shell = CreateObject("Wscript.Shell")

cmd = "powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File ""C:\Scripts\USBKeyPresenceWatcher-Install\USBKeyPresenceLock.ps1"""

' Log command to file
Set fso = CreateObject("Scripting.FileSystemObject")
Set logfile = fso.CreateTextFile("C:\Scripts\USBKeyPresenceWatcher-Install\vbs-debug.txt", True)
logfile.WriteLine "CMD: " & cmd
logfile.Close

shell.Run cmd, 0, False