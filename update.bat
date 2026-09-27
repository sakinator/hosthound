@echo off
title Update Hostreamio Addon
cd /d "%~dp0"

echo ============================================================
echo   ⚡ Updating Hostreamio Addon (Git Pull + Rebuild)
echo ============================================================
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pipeline\update.ps1"
echo.
pause
