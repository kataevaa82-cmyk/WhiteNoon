param(
    [int]$X = -1,
    [int]$Y = -1,
    [string]$Text,
    [string]$AppendText,
    [string]$Keys,
    [int]$Clicks = 1,
    [int]$DelayAfterClickMs = 120
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class YandexConsoleInput {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
'@

[YandexConsoleInput]::SetProcessDPIAware() | Out-Null

$processes = Get-Process msedge, chrome -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 }
$process = $processes |
    Where-Object { $_.MainWindowTitle -match 'Яндекс Игры|Yandex Games|console\.games' } |
    Select-Object -First 1
if ($null -eq $process) { $process = $processes | Select-Object -First 1 }
if ($null -eq $process) { throw "The Yandex Games Console window is not open." }

$rect = New-Object YandexConsoleInput+RECT
[YandexConsoleInput]::GetWindowRect($process.MainWindowHandle, [ref]$rect) | Out-Null
[YandexConsoleInput]::SetForegroundWindow($process.MainWindowHandle) | Out-Null
Start-Sleep -Milliseconds $DelayAfterClickMs

if ($X -ge 0 -and $Y -ge 0) {
    [YandexConsoleInput]::SetCursorPos($rect.Left + $X, $rect.Top + $Y) | Out-Null
    for ($index = 0; $index -lt $Clicks; $index++) {
        [YandexConsoleInput]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero)
        [YandexConsoleInput]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 90
    }
    Start-Sleep -Milliseconds $DelayAfterClickMs
}

if ($PSBoundParameters.ContainsKey("Text")) {
    for ($attempt = 0; $attempt -lt 5; $attempt++) {
        try {
            [System.Windows.Forms.Clipboard]::SetText($Text)
            break
        }
        catch {
            if ($attempt -eq 4) { throw }
            Start-Sleep -Milliseconds 100
        }
    }
    [System.Windows.Forms.SendKeys]::SendWait("^a")
    [System.Windows.Forms.SendKeys]::SendWait("+{INSERT}")
}

if ($PSBoundParameters.ContainsKey("AppendText")) {
    for ($attempt = 0; $attempt -lt 5; $attempt++) {
        try {
            [System.Windows.Forms.Clipboard]::SetText($AppendText)
            break
        }
        catch {
            if ($attempt -eq 4) { throw }
            Start-Sleep -Milliseconds 100
        }
    }
    [System.Windows.Forms.SendKeys]::SendWait("+{INSERT}")
}

if ($PSBoundParameters.ContainsKey("Keys")) {
    [System.Windows.Forms.SendKeys]::SendWait($Keys)
}

Start-Sleep -Milliseconds 350
