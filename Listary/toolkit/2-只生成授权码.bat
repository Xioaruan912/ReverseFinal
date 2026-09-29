@echo off
title Listary 6 Pro 生成授权码
cd /d "%~dp0"
echo ==============================================================
echo   只生成授权码（不修改任何文件、不需要管理员）
echo ==============================================================
echo.
set "EMAIL="
set /p EMAIL=请输入你的邮箱:
if "%EMAIL%"=="" ( echo. & echo [x] 没有输入邮箱。 & pause & exit /b 1 )
echo.
Listary6Pro.exe gen "%EMAIL%"
echo.
echo 把上面 6 行授权码整段复制到 Listary 的激活框即可。
pause
