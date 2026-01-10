:; exec bash "$(dirname "$0")/stop-hook.sh" ; exit
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0stop-hook.ps1"
