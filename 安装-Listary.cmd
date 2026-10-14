@echo off
chcp 65001 >nul
title Install Listary
powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/listary.ps1 | iex"
echo.
pause
