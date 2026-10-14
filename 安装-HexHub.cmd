@echo off
chcp 65001 >nul
title Install HexHub
powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/hexhub.ps1 | iex"
echo.
pause
