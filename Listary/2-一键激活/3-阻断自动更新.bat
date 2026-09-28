@echo off
title Listary 6 Pro 阻断自动更新
cd /d "%~dp0"
net session >nul 2>&1
if errorlevel 1 (
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
Listary6Pro.exe block-update
echo.
pause
