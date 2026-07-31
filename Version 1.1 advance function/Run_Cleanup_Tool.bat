@echo off
:: Check if running from inside ZIP (missing ps1 file)
if not exist "%~dp0cleanup_tool.ps1" (
    color 4F
    echo =======================================================
    echo [ERROR] PLEASE EXTRACT THE ZIP FILE BEFORE RUNNING!
    echo =======================================================
    pause
    exit /B
)

:: Request Admin privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Requesting Administrator privileges...
    powershell -Command "Start-Process '%~dpnx0' -Verb RunAs"
    exit /B
)

:run
chcp 874 >nul

:: Check if Windows Terminal is installed (which supports Thai natively)
where wt.exe >nul 2>&1
if %errorlevel% equ 0 (
    wt.exe powershell.exe -NoExit -ExecutionPolicy Bypass -NoProfile -File "%~dp0cleanup_tool.ps1"
    exit /B
) else (
    :: Fallback to legacy console
    powershell.exe -NoExit -ExecutionPolicy Bypass -NoProfile -File "%~dp0cleanup_tool.ps1"
)