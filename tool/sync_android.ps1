# Synchronizes shared engine and service files from lib/ to android_app/lib/
$sourceFiles = @(
    "badge_service.dart",
    "catalog_service.dart",
    "config.dart",
    "doh_resolver.dart",
    "fanart_service.dart",
    "iptv_service.dart",
    "key_validator.dart",
    "metadata_service.dart",
    "mpd_converter.dart",
    "omdb_service.dart",
    "opensubtitles_service.dart",
    "proxy.dart",
    "proxy_resolver.dart",
    "scraper_engine.dart",
    "scraper_registry.dart",
    "torbox_service.dart",
    "tvdb_service.dart",
    "web_ui.dart"
)

$libDir = Join-Path $PSScriptRoot "..\lib"
$androidLibDir = Join-Path $PSScriptRoot "..\android_app\lib"

Write-Host "Syncing shared files from lib\ to android_app\lib\..." -ForegroundColor Cyan
foreach ($f in $sourceFiles) {
    $src = Join-Path $libDir $f
    $dst = Join-Path $androidLibDir $f
    if (Test-Path $src) {
        Copy-Item -Path $src -Destination $dst -Force
        Write-Host "  -> Synced $f" -ForegroundColor Green
    }
}

$srcScrapers = Join-Path $libDir "upstream\services\scraper"
$dstScrapers = Join-Path $androidLibDir "upstream\services\scraper"
if (Test-Path $srcScrapers) {
    Copy-Item -Path "$srcScrapers\*" -Destination $dstScrapers -Recurse -Force
    Write-Host "  -> Synced upstream scraper directory recursively" -ForegroundColor Green
}

$srcAssets = Join-Path $libDir "assets"
$dstAssets = Join-Path $androidLibDir "assets"
if (Test-Path $srcAssets) {
    if (-not (Test-Path $dstAssets)) { New-Item -ItemType Directory -Path $dstAssets -Force | Out-Null }
    Copy-Item -Path "$srcAssets\*" -Destination $dstAssets -Recurse -Force
    Write-Host "  -> Synced assets directory recursively" -ForegroundColor Green
}

Write-Host "Sync complete!" -ForegroundColor Cyan
