param(
    [Parameter(Mandatory = $true)][int]$X,
    [Parameter(Mandatory = $true)][int]$Y,
    [Parameter(Mandatory = $true)][string]$Path,
    [switch]$Probe
)

$ErrorActionPreference = "Stop"
$resolvedPath = (Resolve-Path -LiteralPath $Path).Path

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class YandexFileUpload {
    public delegate bool WindowCallback(IntPtr handle, IntPtr state);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr handle, out RECT rect);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr handle);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint x, uint y, uint data, UIntPtr extra);
    [DllImport("user32.dll")] public static extern bool EnumWindows(WindowCallback callback, IntPtr state);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr parent, WindowCallback callback, IntPtr state);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr handle);
    [DllImport("user32.dll")] public static extern int GetClassName(IntPtr handle, StringBuilder text, int count);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr handle, StringBuilder text, int count);
    [DllImport("user32.dll")] public static extern int GetDlgCtrlID(IntPtr handle);
    [DllImport("user32.dll")] public static extern IntPtr GetDlgItem(IntPtr dialog, int id);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern bool SetWindowText(IntPtr handle, string text);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr handle, uint message, IntPtr wParam, IntPtr lParam);

    public static IntPtr FindOpenDialog() {
        IntPtr result = IntPtr.Zero;
        EnumWindows((handle, state) => {
            var className = new StringBuilder(64);
            var title = new StringBuilder(128);
            GetClassName(handle, className, className.Capacity);
            GetWindowText(handle, title, title.Capacity);
            // The picker may have a validation warning in front of it. Select the
            // visible dialog that owns the standard file-name combo (control 1148).
            if (className.ToString() == "#32770" && IsWindowVisible(handle) && GetDlgItem(handle, 1148) != IntPtr.Zero) {
                result = handle;
                return false;
            }
            return true;
        }, IntPtr.Zero);
        return result;
    }

    public static IntPtr FindFileNameEdit(IntPtr dialog) {
        IntPtr result = IntPtr.Zero;
        EnumChildWindows(dialog, (handle, state) => {
            var className = new StringBuilder(64);
            GetClassName(handle, className, className.Capacity);
            if (className.ToString() == "Edit" && GetDlgCtrlID(handle) == 1148) {
                result = handle;
                return false;
            }
            return true;
        }, IntPtr.Zero);
        return result;
    }
}
'@

[YandexFileUpload]::SetProcessDPIAware() | Out-Null
$browser = Get-Process msedge, chrome -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -match 'Google Chrome|Microsoft Edge' } |
    Select-Object -First 1
if ($null -eq $browser) { throw "The Yandex Games Console window is not open." }

$dialogHandle = [YandexFileUpload]::FindOpenDialog()
if ($dialogHandle -eq [IntPtr]::Zero) {
    $rect = New-Object YandexFileUpload+RECT
    [YandexFileUpload]::GetWindowRect($browser.MainWindowHandle, [ref]$rect) | Out-Null
    [YandexFileUpload]::SetForegroundWindow($browser.MainWindowHandle) | Out-Null
    [YandexFileUpload]::SetCursorPos($rect.Left + $X, $rect.Top + $Y) | Out-Null
    [YandexFileUpload]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero)
    [YandexFileUpload]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
}

for ($attempt = 0; $attempt -lt 30 -and $dialogHandle -eq [IntPtr]::Zero; $attempt++) {
    Start-Sleep -Milliseconds 100
    $dialogHandle = [YandexFileUpload]::FindOpenDialog()
}
if ($dialogHandle -eq [IntPtr]::Zero) { throw "The file picker did not open." }

Start-Sleep -Milliseconds 500
$fileNameHandle = [YandexFileUpload]::FindFileNameEdit($dialogHandle)
$fileNameComboHandle = [YandexFileUpload]::GetDlgItem($dialogHandle, 1148)
$openButtonHandle = [YandexFileUpload]::GetDlgItem($dialogHandle, 1)
if ($Probe) {
    Write-Output "NativeFileNameHandle=$fileNameHandle"
    Write-Output "NativeOpenButtonHandle=$openButtonHandle"
}
elseif ($fileNameHandle -ne [IntPtr]::Zero -and $openButtonHandle -ne [IntPtr]::Zero) {
    [YandexFileUpload]::SetWindowText($fileNameHandle, $resolvedPath) | Out-Null
    [YandexFileUpload]::SetWindowText($fileNameComboHandle, $resolvedPath) | Out-Null
    # Notify the common file dialog that the editable combo value changed.
    [YandexFileUpload]::SendMessage($dialogHandle, 0x0111, [IntPtr]328828, $fileNameComboHandle) | Out-Null
    [YandexFileUpload]::SendMessage($openButtonHandle, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
    Start-Sleep -Seconds 2
    Write-Output "Uploaded: $resolvedPath"
    return
}

$dialog = [System.Windows.Automation.AutomationElement]::FromHandle($dialogHandle)
$elements = $dialog.FindAll(
    [System.Windows.Automation.TreeScope]::Descendants,
    [System.Windows.Automation.Condition]::TrueCondition
)

if ($Probe) {
    for ($index = 0; $index -lt $elements.Count; $index++) {
        $element = $elements.Item($index)
        $type = $element.Current.ControlType.ProgrammaticName
        if ($type -match 'Edit|Button|ComboBox') {
            [pscustomobject]@{
                Index = $index
                Type = $type
                Name = $element.Current.Name
                AutomationId = $element.Current.AutomationId
                Class = $element.Current.ClassName
            }
        }
    }
    return
}

$fileName = $null
$openButton = $null
for ($index = 0; $index -lt $elements.Count; $index++) {
    $element = $elements.Item($index)
    if ($element.Current.AutomationId -eq '1148') { $fileName = $element }
    if ($element.Current.AutomationId -eq '1' -and $element.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button) {
        $openButton = $element
    }
}
if ($null -eq $fileName) { throw "Could not find the file-name field in the picker." }
if ($null -eq $openButton) { throw "Could not find the Open button in the picker." }

$valuePattern = $fileName.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
$valuePattern.SetValue($resolvedPath)
$invokePattern = $openButton.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
$invokePattern.Invoke()
Start-Sleep -Seconds 2
Write-Output "Uploaded: $resolvedPath"
