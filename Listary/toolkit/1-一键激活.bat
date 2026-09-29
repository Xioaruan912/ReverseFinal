@echo off
title Listary 6 Pro 一键激活
cd /d "%~dp0"
net session >nul 2>&1
if errorlevel 1 (
  echo.
  echo   需要管理员权限，正在弹出 UAC 提权窗口，请点"是"...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
echo ==============================================================
echo   Listary 6 Pro 一键激活
echo ==============================================================
echo.
set "EMAIL="
set /p EMAIL=请输入你的邮箱（用于生成授权码，例如 abc@qq.com）:
if "%EMAIL%"=="" ( echo. & echo [x] 没有输入邮箱，已取消。 & pause & exit /b 1 )
echo.
echo [*] 邮箱: %EMAIL%
echo.
Listary6Pro.exe activate "%EMAIL%" --name "Listary Pro"
echo.
echo --------------------------------------------------------------
echo  若上面出现 自检 : True  即表示成功。
echo  接着按 【双击 Ctrl】 唤出 Listary，标题栏显示 Listary Pro。
echo --------------------------------------------------------------
pause
