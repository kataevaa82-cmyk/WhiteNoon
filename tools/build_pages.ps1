param(
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$SourcePath = "build\web",
    [string]$OutputPath = "build\pages"
)

$ErrorActionPreference = "Stop"
$resolvedProject = (Resolve-Path -LiteralPath $ProjectPath).Path
$source = Join-Path $resolvedProject $SourcePath
$output = Join-Path $resolvedProject $OutputPath
$stub = Join-Path $resolvedProject "tools\pages_sdk_stub.js"
$binaryLoader = Join-Path $resolvedProject "tools\binary_png_loader.js"
$binaryPacker = Join-Path $resolvedProject "tools\pack_pages_binaries.py"

if (-not (Test-Path -LiteralPath (Join-Path $source "index.html"))) {
    throw "Web build is missing. Run tools\build_web.ps1 first."
}
if (-not (Test-Path -LiteralPath $stub)) {
    throw "Pages SDK mock is missing: $stub"
}
if (-not (Test-Path -LiteralPath $binaryLoader) -or -not (Test-Path -LiteralPath $binaryPacker)) {
    throw "Pages binary transport helpers are missing."
}

$resolvedSource = (Resolve-Path -LiteralPath $source).Path
if (-not $resolvedSource.StartsWith($resolvedProject + "\", [StringComparison]::OrdinalIgnoreCase)) {
    throw "Pages source escaped the project directory."
}
if (Test-Path -LiteralPath $output) {
    $resolvedOutput = (Resolve-Path -LiteralPath $output).Path
    if (-not $resolvedOutput.StartsWith((Join-Path $resolvedProject "build") + "\", [StringComparison]::OrdinalIgnoreCase)) {
        throw "Pages cleanup target escaped the build directory."
    }
    Remove-Item -LiteralPath $resolvedOutput -Recurse -Force
}
New-Item -ItemType Directory -Path $output -Force | Out-Null
Copy-Item -Path (Join-Path $resolvedSource "*") -Destination $output -Recurse -Force
Copy-Item -LiteralPath $stub -Destination (Join-Path $output "sdk.js") -Force
Copy-Item -LiteralPath $binaryLoader -Destination (Join-Path $output "binary-png-loader.js") -Force

foreach ($binaryName in @("index.pck", "index.wasm")) {
    $binaryPath = Join-Path $output $binaryName
    $encodedPath = $binaryPath + ".png"
    & python $binaryPacker $binaryPath $encodedPath
    if ($LASTEXITCODE -ne 0) {
        throw "Could not encode $binaryName for GitHub Pages."
    }
    Remove-Item -LiteralPath $binaryPath -Force
}

$indexPath = Join-Path $output "index.html"
$html = Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8
$html = $html.Replace('<script src="/sdk.js" async onload="whiteNoonSdkLoaded()" onerror="whiteNoonSdkFailed()"></script>', '<script src="./sdk.js" async onload="whiteNoonSdkLoaded()" onerror="whiteNoonSdkFailed()"></script>')
$html = $html.Replace('<link rel="preload" href="index.wasm" as="fetch" type="application/wasm" crossorigin="anonymous">', '')
$html = $html.Replace('<link rel="preload" href="index.pck" as="fetch" crossorigin="anonymous">', '')
$html = $html.Replace('<script src="index.js"></script>', '<script src="binary-png-loader.js"></script>' + [Environment]::NewLine + "`t`t<script src=`"index.js`"></script>")
if (-not $html.Contains('<script src="./sdk.js" async onload="whiteNoonSdkLoaded()" onerror="whiteNoonSdkFailed()"></script>')) {
    throw "Could not install the Pages SDK mock reference."
}
if (-not $html.Contains('<script src="binary-png-loader.js"></script>')) {
    throw "Could not install the Pages binary loader reference."
}
if ($html.Contains('rel="preload" href="index.wasm"') -or $html.Contains('rel="preload" href="index.pck"')) {
    throw "Pages preview still contains preloads for binaries replaced by PNG transport."
}
[IO.File]::WriteAllText($indexPath, $html, [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $output ".nojekyll"), "", [Text.UTF8Encoding]::new($false))

$required = @(
    ".nojekyll", "index.html", "index.js", "index.pck.png", "index.wasm.png",
    "index.audio.worklet.js", "index.audio.position.worklet.js", "sdk.js", "binary-png-loader.js"
)
foreach ($file in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $output $file))) {
        throw "Pages file is missing: $file"
    }
}

Write-Output "PAGES_DIR=$output"
Get-ChildItem -LiteralPath $output -File | Sort-Object Name | Select-Object Name, Length
