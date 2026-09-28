# Synchronizes shared engine and service files from lib/ to android_app/lib/
$sourceFiles = @(
    "badge_service.dart",
    "catalog_service.dart",
    "config.dart",
    "doh_resolver.dart",
    "fanart_service.dart",
    "key_validator.dart",
    "metadata_service.dart",
    "mpd_converter.dart",
    "omdb_service.dart",
    "proxy.dart",
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
Write-Host "Sync complete!" -ForegroundColor Cyan
