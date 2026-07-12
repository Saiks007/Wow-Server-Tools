' Launches WowServerControl.ps1 with no console window at all.
' WScript.Shell.Run's 3rd arg (0) = vbHide — the child process has no visible window.
Dim shell, folder
Set shell = CreateObject("WScript.Shell")
folder = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\") - 1)
shell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & folder & "\WowServerControl.ps1""", 0, False
