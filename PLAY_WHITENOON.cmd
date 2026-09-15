@echo off
set "APPDATA=%~dp0.runtime\Roaming"
set "LOCALAPPDATA=%~dp0.runtime\Local"
if not exist "%APPDATA%" mkdir "%APPDATA%"
if not exist "%LOCALAPPDATA%" mkdir "%LOCALAPPDATA%"
cd /d "%~dp0build\windows"
start "WhiteNoon" "WhiteNoon.exe"
