@echo off
chcp 65001 >nul
title Fix Leftovers - Big Cleaning

if not exist "%~dp0Fix_Leftovers.ps1" (
    echo [ERROR] ไม่พบไฟล์ Fix_Leftovers.ps1 - กรุณาแตกไฟล์ ZIP ก่อนใช้งาน
    pause
    exit /B
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Fix_Leftovers.ps1"
