@echo off
title Listary 6 Pro 撤销激活
cd /d "%~dp0"
net session >nul 2>&1
if errorlevel 1 (
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
Listary6Pro.exe clean
echo.
echo 如需把整个设置文件恢复到最早状态，可执行：
echo     Listary6Pro.exe restore-bak
echo.
pause
