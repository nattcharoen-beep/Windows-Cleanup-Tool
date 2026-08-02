@echo off
chcp 65001 >nul
title Check PC - ตรวจเครื่องที่เคยรัน cleanup_tool เวอร์ชันเก่า

if not exist "%~dp0Check_PC.ps1" (
    echo [ERROR] ไม่พบไฟล์ Check_PC.ps1
    echo กรุณาก๊อป Check_PC.bat และ Check_PC.ps1 ไปไว้ในโฟลเดอร์เดียวกัน
    pause
    exit /B
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Check_PC.ps1"
