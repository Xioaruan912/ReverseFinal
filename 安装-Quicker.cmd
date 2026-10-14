@echo off
chcp 65001 >nul
title Install Quicker
powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/quicker.ps1 | iex"
echo.
pause
