param([string]$Output = "build\yandex_console.png")

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class YandexConsoleCapture {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int command);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
'@

[YandexConsoleCapture]::SetProcessDPIAware() | Out-Null

$processes = Get-Process msedge, chrome -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 }
$process = $processes |
    Where-Object { $_.MainWindowTitle -match 'Яндекс Игры|Yandex Games|console\.games' } |
    Select-Object -First 1
if ($null -eq $process) { $process = $processes | Select-Object -First 1 }
if ($null -eq $process) { throw "The Yandex Games Console window is not open." }

[YandexConsoleCapture]::ShowWindow($process.MainWindowHandle, 9) | Out-Null
[YandexConsoleCapture]::SetForegroundWindow($process.MainWindowHandle) | Out-Null
Start-Sleep -Milliseconds 500
$rect = New-Object YandexConsoleCapture+RECT
[YandexConsoleCapture]::GetWindowRect($process.MainWindowHandle, [ref]$rect) | Out-Null
$width = $rect.Right - $rect.Left
$height = $rect.Bottom - $rect.Top
$bitmap = New-Object System.Drawing.Bitmap $width, $height
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
try {
    $graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, [System.Drawing.Size]::new($width, $height))
    $outputPath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $Output))
    $bitmap.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    [pscustomobject]@{ Path = $outputPath; Left = $rect.Left; Top = $rect.Top; Width = $width; Height = $height }
}
finally {
    $graphics.Dispose()
    $bitmap.Dispose()
}
