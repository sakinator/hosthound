@echo off
title Hostreamio Addon
cd /d "%~dp0"

echo ===============================================================
echo        ▶️ Hostreamio Addon (Direct Hosters + Streaming Links + Badges)
echo ===============================================================
echo.

:: ── Find Dart ──────────────────────────────────────────────────────────────
set DART_EXE=
if exist "..\dart-sdk\bin\dart.exe" (
    set "DART_EXE=..\dart-sdk\bin\dart.exe"
) else if exist "dart-sdk\bin\dart.exe" (
    set "DART_EXE=dart-sdk\bin\dart.exe"
) else (
    where dart >nul 2>nul
    if %errorlevel% equ 0 (
        set "DART_EXE=dart"
    )
)

:: ── First-time setup (creates lib\upstream junction + dart pub get) ─────────
if not exist "lib\upstream" (
    if defined DART_EXE (
        echo Running first-time setup...
        "%DART_EXE%" run tool/setup.dart
        echo.
    )
)

:: ── Start server ─────────────────────────────────────────────────────────────
if exist "hostreamio.exe" (
    echo Using compiled binary (hostreamio.exe^)...
    "hostreamio.exe" %*
    goto end
)

if exist "hosthound.exe" (
    echo Using compiled binary (hosthound.exe^)...
    "hosthound.exe" %*
    goto end
)

if exist "unbound.exe" (
    echo Using compiled binary (unbound.exe^)...
    "unbound.exe" %*
    goto end
)

if exist "sakinator-MegaScraper.exe" (
    echo Using compiled binary (sakinator-MegaScraper.exe^)...
    "sakinator-MegaScraper.exe" %*
    goto end
)

if not defined DART_EXE (
    echo [ERROR] Dart SDK not found! Install from https://dart.dev/get-dart
    pause
    exit /b 1
)

echo Using dart run...
"%DART_EXE%" run bin/server.dart %*

:end
pause
