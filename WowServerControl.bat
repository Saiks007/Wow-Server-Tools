@echo off
REM Delegates to the .vbs launcher, which starts PowerShell with no console window at all.
start "" wscript.exe "%~dp0WowServerControl.vbs"
