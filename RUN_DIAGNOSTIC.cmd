@echo off
rem ---------------------------------------------------------------------------
rem WhiteNoon: run with verbose log.
rem
rem ASCII ONLY, AND NO "chcp" HERE. This is not a style preference:
rem
rem  1. A .cmd file with a Cyrillic NAME cannot be invoked from cmd.exe or
rem     PowerShell reliably - the console runs in an OEM codepage and does not
rem     resolve the name. The old ZAPUSTIT_S_DIAGNOSTIKOY.cmd failed with
rem     "is not recognized as an internal or external command".
rem
rem  2. "chcp 65001" inside a batch file that also contains non-ASCII text makes
rem     cmd.exe lose its byte position in the file. Every following line is read
rem     from the wrong offset and gets mangled. That is why the old log said
rem     "'rbose' is not recognized" - the parser ate the start of "--verbose".
rem
rem Keep this file ASCII and keep the Russian text out of the batch layer.
rem ---------------------------------------------------------------------------

set "APPDATA=%~dp0.runtime\Roaming"
set "LOCALAPPDATA=%~dp0.runtime\Local"
if not exist "%APPDATA%" mkdir "%APPDATA%"
if not exist "%LOCALAPPDATA%" mkdir "%LOCALAPPDATA%"

cd /d "%~dp0build\windows"
if not exist "WhiteNoon.exe" (
    echo ERROR: WhiteNoon.exe not found in %CD%
    echo Build it first: tools\build_web.ps1 for web, or export "Windows Desktop".
    pause
    exit /b 1
)

echo Starting WhiteNoon with a verbose log.
echo Log: %CD%\WhiteNoon-launch.log
echo.
rem Path is explicit on purpose. A bare "WhiteNoon.exe" is looked up in PATH, and
rem the current directory is NOT part of that lookup when
rem NoDefaultCurrentDirectoryInExePath is set - which it is in some shells. The
rem file was right there and cmd still answered "is not recognized".
"%~dp0build\windows\WhiteNoon.exe" --verbose > WhiteNoon-launch.log 2>&1
set "WHITE_NOON_EXIT=%ERRORLEVEL%"
echo.
echo WhiteNoon exited with code %WHITE_NOON_EXIT%.
echo The log above is written to WhiteNoon-launch.log next to the exe.
pause
