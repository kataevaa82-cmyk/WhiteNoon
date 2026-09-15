param(
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$runtimeRoot = Join-Path $projectRoot ".runtime"
$outputRoot = Join-Path $projectRoot "build\windows"
$executablePath = Join-Path $outputRoot "WhiteNoon.exe"
$archivePath = Join-Path $projectRoot "build\WhiteNoon-Windows.zip"
$sizeLimit = 100MB

if (-not $GodotPath) {
    $godotCommand = Get-Command "godot.exe" -ErrorAction Stop
    $GodotPath = $godotCommand.Source
}

New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
$resolvedProject = (Resolve-Path -LiteralPath $projectRoot).Path
$resolvedOutput = (Resolve-Path -LiteralPath $outputRoot).Path
if (-not $resolvedOutput.StartsWith($resolvedProject + [IO.Path]::DirectorySeparatorChar)) {
    throw "Windows output escaped the project directory."
}

$env:APPDATA = Join-Path $runtimeRoot "Roaming"
$env:LOCALAPPDATA = Join-Path $runtimeRoot "Local"

& $GodotPath --headless --path $resolvedProject --export-release "Windows Desktop" $executablePath
if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
    throw "Godot failed to export the Windows build (exit $LASTEXITCODE)."
}
if (-not (Test-Path -LiteralPath $executablePath)) {
    throw "Godot did not create the Windows executable: $executablePath"
}

# Godot отдаёт управление раньше, чем Windows дописывает exe, и файл ещё какое-то
# время растёт: Compress-Archive успевал прочитать усечённую копию. Двух совпавших
# замеров мало — файл дописывается рывками. Ждём несколько подряд, а после упаковки
# сверяем и при расхождении пакуем заново.
function Wait-ForStableFile {
    param([string]$Path)
    $lastSize = -1
    $stableCount = 0
    for ($attempt = 0; $attempt -lt 120; $attempt++) {
        $size = (Get-Item -LiteralPath $Path).Length
        if ($size -eq $lastSize) {
            $stableCount++
            if ($stableCount -ge 6) { return $size }
        }
        else {
            $stableCount = 0
            $lastSize = $size
        }
        Start-Sleep -Milliseconds 500
    }
    return (Get-Item -LiteralPath $Path).Length
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$exeName = Split-Path -Leaf $executablePath
$packedOk = $false
for ($try = 1; $try -le 4; $try++) {
    $exeSize = Wait-ForStableFile -Path $executablePath
    if (Test-Path -LiteralPath $archivePath) {
        Remove-Item -LiteralPath $archivePath -Force
    }
    Compress-Archive -Path (Join-Path $resolvedOutput "*") -DestinationPath $archivePath -CompressionLevel Optimal
    $verifyArchive = [IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
        $packedExe = $verifyArchive.Entries | Where-Object { $_.FullName -eq $exeName }
        if ($null -eq $packedExe) {
            throw "Windows archive does not contain $exeName."
        }
        $packedSize = $packedExe.Length
    }
    finally {
        $verifyArchive.Dispose()
    }
    $diskSize = (Get-Item -LiteralPath $executablePath).Length
    if ($packedSize -eq $diskSize) {
        $packedOk = $true
        $exeSize = $diskSize
        break
    }
    Write-Output "RETRY=archive held $packedSize bytes against $diskSize on disk; repacking."
}
if (-not $packedOk) {
    throw "Windows archive keeps holding a stale executable after 4 attempts."
}

$exeSize = (Get-Item -LiteralPath $executablePath).Length
$archiveSize = (Get-Item -LiteralPath $archivePath).Length

if ($archiveSize -ge $sizeLimit) {
    throw "Windows distribution archive exceeds 100 MiB: $archiveSize bytes."
}

Write-Output "WINDOWS_EXE=$executablePath"
Write-Output "WINDOWS_EXE_BYTES=$exeSize"
Write-Output "WINDOWS_ARCHIVE=$archivePath"
Write-Output "WINDOWS_ARCHIVE_BYTES=$archiveSize"
Write-Output "NOTE=The official Godot 4.7 release template alone is larger than 100 MB; distribute the checked ZIP archive."
