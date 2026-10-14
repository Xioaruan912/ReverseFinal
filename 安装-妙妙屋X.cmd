@echo off
chcp 65001 >nul
title Install MiaomiaowuX
powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/miaomiaowux.ps1 | iex"
echo.
pause
