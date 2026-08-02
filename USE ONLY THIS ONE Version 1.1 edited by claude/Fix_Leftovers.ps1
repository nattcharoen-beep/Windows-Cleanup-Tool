# =============================================================================
# Fix_Leftovers.ps1
# เก็บกวาดของที่ค้างจากการรัน cleanup_tool.ps1 เวอร์ชันเก่า
#   1. ถอน scheduled task WeeklyTempCleanup / WeeklyRestorePoint
#   2. เปิด Network Receive Window Auto-Tuning กลับเป็น normal
# รันครั้งเดียวพอ ไม่ต้องรันซ้ำ
# =============================================================================

# --- ขอสิทธิ์ Administrator ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "กำลังขอสิทธิ์ Administrator..." -ForegroundColor Yellow
    try {
        Start-Process powershell.exe -ArgumentList @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`""
        ) -Verb RunAs
    } catch {
        Write-Host "ขอสิทธิ์ไม่สำเร็จ กรุณาคลิกขวาที่ Fix_Leftovers.bat แล้วเลือก Run as Administrator" -ForegroundColor Red
        Read-Host "กด Enter เพื่อปิด"
    }
    exit
}

$OutputEncoding = [System.Text.Encoding]::UTF8
$taskNames = @("WeeklyTempCleanup", "WeeklyRestorePoint")

function Get-AutoTuneLevel {
    $line = (netsh interface tcp show global) | Select-String "Auto-Tuning Level"
    if ($line) { ($line.ToString() -split ':')[-1].Trim() } else { "อ่านค่าไม่ได้" }
}

Write-Host ""
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host "  เก็บกวาดของที่ค้างจาก cleanup_tool เวอร์ชันเก่า" -ForegroundColor Cyan
Write-Host "===============================================================" -ForegroundColor Cyan

# --- สถานะก่อนแก้ ---
Write-Host "`n[ สถานะตอนนี้ ]" -ForegroundColor Yellow
$found = @()
foreach ($t in $taskNames) {
    $task = Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue
    if ($task) {
        $found += $t
        Write-Host "  พบงานตั้งเวลา : $t  (สถานะ: $($task.State))" -ForegroundColor White
    } else {
        Write-Host "  ไม่พบงานตั้งเวลา : $t" -ForegroundColor DarkGray
    }
}
$beforeTune = Get-AutoTuneLevel
Write-Host "  Auto-Tuning   : $beforeTune" -ForegroundColor White

# --- ไม่มีอะไรต้องทำ ---
if ($found.Count -eq 0 -and $beforeTune -eq 'normal') {
    Write-Host "`nเครื่องเรียบร้อยอยู่แล้ว ไม่มีอะไรต้องแก้" -ForegroundColor Green
    Read-Host "`nกด Enter เพื่อปิด"
    exit
}

# --- สรุปสิ่งที่จะทำ ---
Write-Host "`n[ สิ่งที่จะทำ ]" -ForegroundColor Yellow
if ($found.Count -gt 0) {
    foreach ($t in $found) { Write-Host "  - ถอนงานตั้งเวลา $t ออกจากเครื่อง" -ForegroundColor White }
} else {
    Write-Host "  - (ไม่มีงานตั้งเวลาต้องถอน)" -ForegroundColor DarkGray
}
if ($beforeTune -ne 'normal') {
    Write-Host "  - เปลี่ยน Auto-Tuning จาก '$beforeTune' เป็น 'normal'" -ForegroundColor White
} else {
    Write-Host "  - (Auto-Tuning เป็น normal อยู่แล้ว)" -ForegroundColor DarkGray
}

Write-Host "`nทั้งสองอย่างย้อนกลับได้ ไม่แตะไฟล์ส่วนตัว" -ForegroundColor DarkGray
$ans = Read-Host "`nดำเนินการเลยไหม? (y/n) [n]"
if ($ans -ne 'y') {
    Write-Host "ยกเลิก ไม่ได้แก้อะไร" -ForegroundColor Yellow
    Read-Host "`nกด Enter เพื่อปิด"
    exit
}

# --- 1. ถอน scheduled task ---
Write-Host "`n[ 1/2 ] ถอนงานตั้งเวลา..." -ForegroundColor Cyan
foreach ($t in $found) {
    try {
        Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction Stop
        Write-Host "  [สำเร็จ] ถอน $t แล้ว" -ForegroundColor Green
    } catch {
        Write-Host "  [ผิดพลาด] ถอน $t ไม่สำเร็จ: $($_.Exception.Message)" -ForegroundColor Red
    }
}
if ($found.Count -eq 0) { Write-Host "  ข้าม ไม่มีงานต้องถอน" -ForegroundColor DarkGray }

# --- 2. Auto-Tuning ---
Write-Host "`n[ 2/2 ] ตั้งค่า Network Auto-Tuning..." -ForegroundColor Cyan
if ($beforeTune -ne 'normal') {
    netsh int tcp set global autotuninglevel=normal | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [สำเร็จ] ตั้ง Auto-Tuning เป็น normal แล้ว" -ForegroundColor Green
    } else {
        Write-Host "  [ผิดพลาด] netsh คืนค่า exit code $LASTEXITCODE" -ForegroundColor Red
    }
} else {
    Write-Host "  ข้าม เป็น normal อยู่แล้ว" -ForegroundColor DarkGray
}

# --- ตรวจผลจริงหลังแก้ ---
Write-Host "`n===============================================================" -ForegroundColor Cyan
Write-Host "  ตรวจผลหลังแก้" -ForegroundColor Cyan
Write-Host "===============================================================" -ForegroundColor Cyan
$stillThere = @()
foreach ($t in $taskNames) {
    if (Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue) { $stillThere += $t }
}
if ($stillThere.Count -eq 0) {
    Write-Host "  งานตั้งเวลา : ถอนออกหมดแล้ว" -ForegroundColor Green
} else {
    Write-Host "  งานตั้งเวลา : ยังเหลือ $($stillThere -join ', ')" -ForegroundColor Red
}
$afterTune = Get-AutoTuneLevel
if ($afterTune -eq 'normal') {
    Write-Host "  Auto-Tuning : $afterTune" -ForegroundColor Green
} else {
    Write-Host "  Auto-Tuning : $afterTune  (ยังไม่เป็น normal)" -ForegroundColor Red
}

Write-Host "`nเสร็จแล้ว ไม่ต้องรันไฟล์นี้ซ้ำอีก" -ForegroundColor Green
Write-Host "ถ้าอยากย้อน Auto-Tuning กลับ ใช้คำสั่ง: netsh int tcp set global autotuninglevel=disabled" -ForegroundColor DarkGray
Read-Host "`nกด Enter เพื่อปิด"
