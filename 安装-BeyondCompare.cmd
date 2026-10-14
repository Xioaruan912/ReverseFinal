@echo off
chcp 65001 >nul
title Install Beyond Compare
powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/beyondcompare.ps1 | iex"
echo.
pause
