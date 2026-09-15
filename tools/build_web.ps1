param(
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$runtimeRoot = Join-Path $projectRoot ".runtime"
$templateRoot = Join-Path $runtimeRoot "Roaming\Godot\export_templates\4.7.1.stable"
$templateZip = Join-Path $templateRoot "web_nothreads_release.zip"
$outputRoot = Join-Path $projectRoot "build\web"
$archivePath = Join-Path $projectRoot "build\WhiteNoon-Yandex.zip"
$loaderBackground = Join-Path $projectRoot "assets\branding\menu_loader_background.jpg"
$loaderMark = Join-Path $projectRoot "assets\branding\white_noon_logo_mark.png"
$promoRoot = Join-Path $projectRoot "promo\yandex"

if (-not (Test-Path -LiteralPath $templateZip)) {
    throw "Godot Web template not found: $templateZip"
}
foreach ($brandingFile in @($loaderBackground, $loaderMark)) {
    if (-not (Test-Path -LiteralPath $brandingFile)) {
        throw "Web loader branding asset not found: $brandingFile"
    }
}

Add-Type -AssemblyName System.Drawing
foreach ($platform in @(
    @{ Name = "desktop"; Path = Join-Path $promoRoot "screenshots" },
    @{ Name = "mobile"; Path = Join-Path $promoRoot "screenshots_mobile" }
)) {
    foreach ($language in @("ru", "en")) {
        $screenshotRoot = Join-Path $platform.Path $language
        if (-not (Test-Path -LiteralPath $screenshotRoot)) {
            throw "Yandex $($platform.Name) screenshot directory is missing: $screenshotRoot"
        }
        $screenshots = @(Get-ChildItem -LiteralPath $screenshotRoot -File | Where-Object { $_.Extension -in @(".png", ".jpg", ".jpeg") })
        if ($screenshots.Count -lt 2) {
            throw "Yandex $($platform.Name)/$language requires at least 2 screenshots; found $($screenshots.Count)."
        }
        foreach ($screenshot in $screenshots) {
            $image = [Drawing.Image]::FromFile($screenshot.FullName)
            try {
                $longSide = [Math]::Max($image.Width, $image.Height)
                if ($image.Width * 9 -ne $image.Height * 16 -or $longSide -lt 1280 -or $longSide -gt 2560) {
                    throw "Invalid Yandex screenshot dimensions: $($screenshot.FullName) ($($image.Width)x$($image.Height))."
                }
                if ($image.PixelFormat -ne [Drawing.Imaging.PixelFormat]::Format24bppRgb) {
                    throw "Yandex screenshot is not 24-bit RGB: $($screenshot.FullName) ($($image.PixelFormat))."
                }
            }
            finally {
                $image.Dispose()
            }
        }
    }
}

foreach ($promoAsset in @(
    @{ Path = Join-Path $promoRoot "icon_512.png"; Width = 512; Height = 512 },
    @{ Path = Join-Path $promoRoot "cover_ru_800x470.png"; Width = 800; Height = 470 },
    @{ Path = Join-Path $promoRoot "cover_en_800x470.png"; Width = 800; Height = 470 },
    @{ Path = Join-Path $promoRoot "showcase_ru_1560x520.jpg"; Width = 1560; Height = 520 },
    @{ Path = Join-Path $promoRoot "showcase_en_1560x520.jpg"; Width = 1560; Height = 520 }
)) {
    if (-not (Test-Path -LiteralPath $promoAsset.Path)) {
        throw "Yandex promo asset is missing: $($promoAsset.Path)"
    }
    $image = [Drawing.Image]::FromFile($promoAsset.Path)
    try {
        if ($image.Width -ne $promoAsset.Width -or $image.Height -ne $promoAsset.Height) {
            throw "Invalid Yandex promo dimensions: $($promoAsset.Path) ($($image.Width)x$($image.Height))."
        }
    }
    finally {
        $image.Dispose()
    }
}

if (-not $GodotPath) {
    $godotCommand = Get-Command "godot_console.exe" -ErrorAction Stop
    $GodotPath = $godotCommand.Source
}

New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
$resolvedOutput = (Resolve-Path -LiteralPath $outputRoot).Path
$resolvedProject = (Resolve-Path -LiteralPath $projectRoot).Path
if (-not $resolvedOutput.StartsWith($resolvedProject + [IO.Path]::DirectorySeparatorChar)) {
    throw "Web output escaped the project directory."
}

Get-ChildItem -LiteralPath $resolvedOutput -Force | ForEach-Object {
    Remove-Item -LiteralPath $_.FullName -Recurse -Force
}

$env:APPDATA = Join-Path $runtimeRoot "Roaming"
$env:LOCALAPPDATA = Join-Path $runtimeRoot "Local"

& $GodotPath --headless --path $resolvedProject --export-pack "Yandex Games (Web)" (Join-Path $resolvedOutput "index.pck")
if ($LASTEXITCODE -ne 0) {
    throw "Godot failed to build the Web project pack (exit $LASTEXITCODE)."
}

$stageRoot = Join-Path ([IO.Path]::GetTempPath()) ("white_noon_web_" + [guid]::NewGuid().ToString("N"))
try {
    New-Item -ItemType Directory -Path $stageRoot | Out-Null
    Expand-Archive -LiteralPath $templateZip -DestinationPath $stageRoot

    Copy-Item -LiteralPath (Join-Path $stageRoot "godot.js") -Destination (Join-Path $resolvedOutput "index.js") -Force
    Copy-Item -LiteralPath (Join-Path $stageRoot "godot.wasm") -Destination (Join-Path $resolvedOutput "index.wasm") -Force
    Copy-Item -LiteralPath (Join-Path $stageRoot "godot.audio.worklet.js") -Destination (Join-Path $resolvedOutput "index.audio.worklet.js") -Force
    Copy-Item -LiteralPath (Join-Path $stageRoot "godot.audio.position.worklet.js") -Destination (Join-Path $resolvedOutput "index.audio.position.worklet.js") -Force
    Copy-Item -LiteralPath $loaderBackground -Destination (Join-Path $resolvedOutput "loader_bg.jpg") -Force
    Copy-Item -LiteralPath $loaderMark -Destination (Join-Path $resolvedOutput "loader_mark.png") -Force

    $packSize = (Get-Item -LiteralPath (Join-Path $resolvedOutput "index.pck")).Length
    $wasmSize = (Get-Item -LiteralPath (Join-Path $resolvedOutput "index.wasm")).Length
    $config = [ordered]@{
        args = @()
        canvasResizePolicy = 2
        emscriptenPoolSize = 8
        ensureCrossOriginIsolationHeaders = $false
        executable = "index"
        experimentalVK = $false
        fileSizes = [ordered]@{
            "index.pck" = $packSize
            "index.wasm" = $wasmSize
        }
        focusCanvas = $true
        gdextensionLibs = @()
        godotPoolSize = 4
    } | ConvertTo-Json -Compress -Depth 5

    $html = Get-Content -LiteralPath (Join-Path $stageRoot "godot.html") -Raw -Encoding UTF8
    $projectName = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("0JHQtdC70YvQuSDQn9C+0LvQtNC10L3RjA=="))
    $html = $html.Replace('$GODOT_PROJECT_NAME', $projectName)
    $html = $html.Replace('$GODOT_SPLASH_CLASSES', 'show-image--true fullsize--false use-filter--true')
    $html = $html.Replace('$GODOT_SPLASH_COLOR', '#140b05')
    $headInclude = @'
<!-- Start the engine independently of the platform network request. -->
<link rel="preload" href="index.wasm" as="fetch" type="application/wasm" crossorigin="anonymous">
<link rel="preload" href="index.pck" as="fetch" crossorigin="anonymous">
<link rel="icon" href="loader_mark.png" type="image/png">
<meta name="screen-orientation" content="landscape">
<meta name="x5-orientation" content="landscape">
<script>
window.whiteNoonSdkLoadState = "loading";
window.whiteNoonSdkLoaded = function () {
    window.whiteNoonSdkLoadState = "ready";
    window.dispatchEvent(new Event("white-noon-sdk-loaded"));
};
window.whiteNoonSdkFailed = function () {
    window.whiteNoonSdkLoadState = "error";
    window.dispatchEvent(new Event("white-noon-sdk-failed"));
};
</script>
<!-- Yandex Games provides /sdk.js inside the game iframe. Async keeps a slow
     platform response from blocking the Godot loader and the playable menu. -->
<script src="/sdk.js" async onload="whiteNoonSdkLoaded()" onerror="whiteNoonSdkFailed()"></script>
<style>
html, body, canvas {
    -webkit-touch-callout: none;
    -webkit-user-select: none;
    user-select: none;
    touch-action: none;
}
html, body {
    margin: 0;
    width: 100%;
    height: 100%;
    overflow: hidden;
    overscroll-behavior: none;
    background: #140b05;
}
#status {
    isolation: isolate;
    overflow: hidden;
    background: #140b05 url("loader_bg.jpg") center center / cover no-repeat;
}
#status::before {
    content: "";
    position: absolute;
    inset: 0;
    z-index: 0;
    background:
        radial-gradient(circle at 50% 35%, rgba(255, 244, 205, 0.08), rgba(16, 10, 8, 0.18) 48%, rgba(8, 5, 4, 0.76) 100%),
        linear-gradient(to bottom, rgba(18, 10, 6, 0.04), rgba(14, 8, 6, 0.62));
}
#status::after {
    content: "\0411\0415\041B\042B\0419\0020\041F\041E\041B\0414\0415\041D\042C\A WHITE NOON";
    white-space: pre;
    position: absolute;
    left: 5vw;
    right: 5vw;
    top: calc(50% + 42px);
    z-index: 1;
    color: #fff0c6;
    font-family: Georgia, "Times New Roman", serif;
    font-size: clamp(24px, 3.2vw, 48px);
    font-weight: 700;
    line-height: 0.92;
    letter-spacing: 0.16em;
    text-align: center;
    text-shadow: 0 3px 18px rgba(25, 4, 2, 0.94);
}
#status-splash {
    display: block !important;
    width: clamp(236px, 31vw, 420px);
    height: clamp(118px, 15.5vw, 210px);
    z-index: 1;
    object-fit: contain;
    filter: drop-shadow(0 14px 24px rgba(20, 3, 2, 0.92));
    transform: translateY(-72px);
}
#status-progress {
    z-index: 2;
    bottom: 11%;
    width: min(480px, 68vw);
    height: 8px;
    overflow: hidden;
    border: 1px solid rgba(255, 222, 139, 0.58);
    border-radius: 999px;
    background: rgba(24, 12, 9, 0.78);
    accent-color: #d8a64b;
}
#status-progress::-webkit-progress-bar {
    background: rgba(20, 14, 11, 0.86);
}
#status-progress::-webkit-progress-value {
    background: linear-gradient(90deg, #6f1a12, #d7ac5c, #fff0c8);
}
#status-progress::-moz-progress-bar {
    background: linear-gradient(90deg, #6f1a12, #d7ac5c, #fff0c8);
}
#status-notice {
    z-index: 3;
    color: #fff0cf;
    border-color: rgba(229, 178, 91, 0.72);
    background: rgba(41, 18, 14, 0.94);
}
#orientation-notice {
    display: none;
    position: fixed;
    inset: 0;
    z-index: 1000;
    align-items: center;
    justify-content: center;
    padding: 9vw;
    box-sizing: border-box;
    color: #fff0c6;
    background: #140b05 url("loader_bg.jpg") center center / cover no-repeat;
    font-family: Georgia, "Times New Roman", serif;
    font-size: clamp(22px, 6vw, 38px);
    font-weight: 700;
    line-height: 1.25;
    letter-spacing: 0.04em;
    text-align: center;
    text-shadow: 0 3px 18px rgba(25, 4, 2, 0.94);
}
#orientation-notice::before {
    content: "";
    position: absolute;
    inset: 0;
    z-index: -1;
    background: rgba(14, 8, 6, 0.66);
}
@media (orientation: portrait) and (pointer: coarse) {
    #orientation-notice {
        display: flex;
    }
}
</style>
<script>
(function () {
    window.whiteNoonLoaderHidden = false;
    var blockBrowserGesture = function (event) { event.preventDefault(); };
    document.addEventListener('contextmenu', blockBrowserGesture, { passive: false });
    document.addEventListener('selectstart', blockBrowserGesture, { passive: false });
    document.addEventListener('dragstart', blockBrowserGesture, { passive: false });
    document.addEventListener('touchmove', function (event) {
        if (event.target && event.target.tagName === 'CANVAS') event.preventDefault();
    }, { passive: false });
    window.addEventListener('keydown', function (event) {
        if (event.code === 'Space' || event.code.indexOf('Arrow') === 0) event.preventDefault();
    }, { passive: false });
    var requestLandscape = function () {
        if (!screen.orientation || typeof screen.orientation.lock !== 'function') return;
        screen.orientation.lock('landscape').catch(function () {});
    };
    requestLandscape();
    window.addEventListener('pointerdown', requestLandscape, { passive: true });
    window.addEventListener('touchend', requestLandscape, { passive: true });
})();
</script>
'@
    $html = $html.Replace('$GODOT_HEAD_INCLUDE', $headInclude)
    $html = $html.Replace('$GODOT_SPLASH', 'loader_mark.png')
    $html = $html.Replace('$GODOT_URL', 'index.js')
    $html = $html.Replace('$GODOT_CONFIG', $config)
    $html = $html.Replace('$GODOT_THREADS_ENABLED', 'false')
    $html = $html.Replace('<html lang="en">', '<html lang="ru">')
    $orientationNotice = @'
<body>
		<div id="orientation-notice" role="status" aria-live="polite">&#x041F;&#x041E;&#x0412;&#x0415;&#x0420;&#x041D;&#x0418;&#x0422;&#x0415; &#x0423;&#x0421;&#x0422;&#x0420;&#x041E;&#x0419;&#x0421;&#x0422;&#x0412;&#x041E;<br>ROTATE YOUR DEVICE</div>
'@
    $html = $html.Replace('<body>', $orientationNotice.TrimEnd())
    $loaderHiddenNeedle = 'statusOverlay.remove();'
    if (-not $html.Contains($loaderHiddenNeedle)) {
        throw "Godot HTML loader completion hook was not found."
    }
    $loaderHiddenHook = @'
statusOverlay.remove();
			window.whiteNoonLoaderHidden = true;
			if (window.whiteNoonSendGameReady) window.whiteNoonSendGameReady();
'@
    $html = $html.Replace($loaderHiddenNeedle, $loaderHiddenHook.TrimEnd())
    [IO.File]::WriteAllText((Join-Path $resolvedOutput "index.html"), $html, [Text.UTF8Encoding]::new($false))
}
finally {
    if (Test-Path -LiteralPath $stageRoot) {
        $stageLeaf = Split-Path -Leaf $stageRoot
        $rawTempRoot = [IO.Path]::GetTempPath()
        if (-not $stageRoot.StartsWith($rawTempRoot, [StringComparison]::OrdinalIgnoreCase) -or -not $stageLeaf.StartsWith("white_noon_web_")) {
            throw "Temporary cleanup target escaped the temp directory."
        }
        Remove-Item -LiteralPath $stageRoot -Recurse -Force
    }
}

$requiredFiles = @(
    "index.html",
    "index.js",
    "index.pck",
    "index.wasm",
    "index.audio.worklet.js",
    "index.audio.position.worklet.js",
    "loader_bg.jpg",
    "loader_mark.png"
)
foreach ($requiredFile in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $resolvedOutput $requiredFile))) {
        throw "Required Yandex build file is missing: $requiredFile"
    }
}

$webFiles = @(Get-ChildItem -LiteralPath $resolvedOutput -File -Recurse)
$unpackedSize = ($webFiles | Measure-Object -Property Length -Sum).Sum
if ($unpackedSize -ge 100MB) {
    throw "Unpacked Yandex build exceeds the 100 MiB platform limit: $unpackedSize bytes."
}
foreach ($file in $webFiles) {
    $outputPrefix = $resolvedOutput.TrimEnd('\') + '\'
    $relative = $file.FullName.Substring($outputPrefix.Length).Replace('\', '/')
    if ($relative.Contains(' ') -or $relative -match '[^\x00-\x7F]') {
        throw "Yandex build path contains spaces or non-ASCII characters: $relative"
    }
}
$finalHtml = Get-Content -LiteralPath (Join-Path $resolvedOutput "index.html") -Raw -Encoding UTF8
foreach ($contract in @('/sdk.js', 'async onload="whiteNoonSdkLoaded()"', 'rel="preload" href="index.wasm"', 'rel="icon" href="loader_mark.png"', 'screen-orientation', 'orientation-notice', "screen.orientation.lock('landscape')", 'contextmenu', 'overscroll-behavior', 'loader_bg.jpg', 'loader_mark.png', 'WHITE NOON', 'whiteNoonLoaderHidden = true', 'whiteNoonSendGameReady')) {
    if (-not $finalHtml.Contains($contract)) {
        throw "Yandex HTML contract is missing: $contract"
    }
}
$serviceSource = Get-Content -LiteralPath (Join-Path $resolvedProject "scripts\yandex_service.gd") -Raw -Encoding UTF8
foreach ($contract in @('LoadingAPI.ready()', 'whiteNoonSendGameReady', '!window.whiteNoonGameReadyRequested || !window.whiteNoonLoaderHidden || !window.ysdk || window.whiteNoonGameReadySent', 'white-noon-sdk-loaded', 'whiteNoonSdkLoadState', 'GameplayAPI.start()', "ysdk.on('game_api_pause'", 'getPlayer()', 'setData(', 'localStorage.setItem', 'showFullscreenAdv(', 'feedback.canReview()', 'feedback.requestReview()')) {
    if (-not $serviceSource.Contains($contract)) {
        throw "Yandex SDK integration contract is missing: $contract"
    }
}

if (Test-Path -LiteralPath $archivePath) {
    Remove-Item -LiteralPath $archivePath -Force
}
Compress-Archive -Path (Join-Path $resolvedOutput "*") -DestinationPath $archivePath -CompressionLevel Optimal

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
try {
    $rootIndex = $archive.Entries | Where-Object { $_.FullName -eq 'index.html' }
    if ($null -eq $rootIndex) {
        throw "Yandex archive does not contain index.html at its root."
    }
}
finally {
    $archive.Dispose()
}

Write-Output "WEB_DIR=$resolvedOutput"
Write-Output "ARCHIVE=$archivePath"
Write-Output "UNPACKED_BYTES=$unpackedSize"
Get-ChildItem -LiteralPath $resolvedOutput -File | Sort-Object Name | Select-Object Name, Length
