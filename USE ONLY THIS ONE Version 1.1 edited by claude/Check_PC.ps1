# =============================================================================
# Check_PC.ps1
# ตรวจเครื่องที่เคยรัน cleanup_tool เวอร์ชันเก่า แล้วแก้เฉพาะจุดที่เสี่ยงจริง
#
# ใช้กับเครื่องไหนก็ได้ ไม่ต้องมี cleanup_tool อยู่ในเครื่องนั้น
# สคริปต์อ่านสถานะจริงของเครื่อง จึงไม่สำคัญว่าเคยรันเวอร์ชันไหน
#
# ตรวจ 5 อย่างที่เสี่ยง + รายงานอีก 7 อย่างที่เป็นแค่ความชอบ
# ไม่แก้อะไรจนกว่าจะกด y
# =============================================================================

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "กำลังขอสิทธิ์ Administrator..." -ForegroundColor Yellow
    try {
        Start-Process powershell.exe -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-File","`"$PSCommandPath`"") -Verb RunAs
    } catch {
        Write-Host "ขอสิทธิ์ไม่สำเร็จ - คลิกขวาที่ Check_PC.bat แล้วเลือก Run as Administrator" -ForegroundColor Red
        Read-Host "กด Enter เพื่อปิด"
    }
    exit
}

$ssPath   = "HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy"
$bgPath   = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"
$taskName = @("WeeklyTempCleanup", "WeeklyRestorePoint")
$todo     = @()

function RegVal($path, $name) {
    if (-not (Test-Path $path)) { return $null }
    (Get-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue).$name
}
function Line($mark, $color, $text) { Write-Host ("  [{0}] {1}" -f $mark, $text) -ForegroundColor $color }

Write-Host ""
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host "  ตรวจเครื่องที่เคยรัน cleanup_tool เวอร์ชันเก่า" -ForegroundColor Cyan
Write-Host "  เครื่อง: $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host "===============================================================" -ForegroundColor Cyan

# ---------------------------------------------------------------- 1
Write-Host "`n[ 1 ] Storage Sense - สวิตช์ล้างโฟลเดอร์ Downloads" -ForegroundColor Yellow
$ss256 = RegVal $ssPath "256"
$ss512 = RegVal $ssPath "512"
if ($null -ne $ss256 -and $ss256 -ne 0) {
    Line "เสี่ยง" Red "พบค่า 256 = $ss256 (สวิตช์ล้าง Downloads ถูกเปิด)"
    if ($ss512 -eq 0 -or $null -eq $ss512) {
        Line "     " DarkGray "เกณฑ์วัน (512) = $ss512 -> ยังไม่ลบจริง แต่ควรเอาออก"
    } else {
        Line "อันตราย" Red "เกณฑ์วัน (512) = $ss512 วัน -> ไฟล์ใน Downloads จะถูกลบจริง!"
    }
    $todo += "ss"
} else {
    Line "ผ่าน" Green "ไม่พบสวิตช์ล้าง Downloads"
}

# ---------------------------------------------------------------- 2
Write-Host "`n[ 2 ] งานตั้งเวลาที่ฝังไว้ถาวร" -ForegroundColor Yellow
$foundTasks = @()
foreach ($t in $taskName) {
    if (Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue) { $foundTasks += $t }
}
if ($foundTasks.Count -gt 0) {
    foreach ($t in $foundTasks) { Line "เสี่ยง" Red "พบงาน $t (รันเป็น SYSTEM ทุกสัปดาห์)" }
    $todo += "task"
} else {
    Line "ผ่าน" Green "ไม่พบงานตั้งเวลาที่เครื่องมือสร้าง"
}

# ---------------------------------------------------------------- 3
Write-Host "`n[ 3 ] Network Auto-Tuning" -ForegroundColor Yellow
$tuneLine = (netsh interface tcp show global) | Select-String "Auto-Tuning Level"
$tune = if ($tuneLine) { ($tuneLine.ToString() -split ':')[-1].Trim() } else { "?" }
if ($tune -ne 'normal') {
    Line "เสี่ยง" Yellow "Auto-Tuning = $tune (ทำให้เน็ตความเร็วสูงช้าลง)"
    $todo += "tune"
} else {
    Line "ผ่าน" Green "Auto-Tuning = normal"
}

# ---------------------------------------------------------------- 4
Write-Host "`n[ 4 ] Print Spooler (บริการปริ้นเตอร์)" -ForegroundColor Yellow
$sp = Get-CimInstance Win32_Service -Filter "Name='Spooler'" -ErrorAction SilentlyContinue
if ($sp -and $sp.StartMode -eq 'Disabled') {
    Line "เสี่ยง" Red "Spooler = Disabled -> ปริ้นไม่ได้เลย"
    $todo += "spooler"
} elseif ($sp -and $sp.StartMode -ne 'Auto') {
    Line "เตือน" Yellow "Spooler = $($sp.StartMode) (ปริ้นได้ แต่ไม่ใช่ค่าเริ่มต้น)"
    $todo += "spooler"
} else {
    Line "ผ่าน" Green "Spooler = $($sp.StartMode) / $($sp.State)"
}

# ---------------------------------------------------------------- 5
Write-Host "`n[ 5 ] Background Apps (มีผลกับ Omen Hub / ปุ่มลัดของโน้ตบุ๊ก)" -ForegroundColor Yellow
$bg = RegVal $bgPath "GlobalUserDisabled"
if ($bg -eq 1) {
    Line "เสี่ยง" Red "Background Apps ถูกปิด -> ปุ่มลัด/แอปพื้นหลังอาจไม่ทำงาน"
    $todo += "bg"
} else {
    Line "ผ่าน" Green "Background Apps ไม่ได้ถูกปิด"
}

# ---------------------------------------------------------------- รายงานเฉย ๆ
Write-Host "`n---------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host " ค่าต่อไปนี้เป็น 'ความชอบ' ไม่ใช่ความเสียหาย - รายงานให้ทราบเฉย ๆ" -ForegroundColor DarkGray
Write-Host "---------------------------------------------------------------" -ForegroundColor DarkGray
$info = @(
    @{ n="Cortana";              v=(RegVal "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "AllowCortana") }
    @{ n="Telemetry";            v=(RegVal "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry") }
    @{ n="Transparency";         v=(RegVal "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" "EnableTransparency") }
    @{ n="Game DVR";             v=(RegVal "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" "AppCaptureEnabled") }
    @{ n="HAGS (GPU Scheduling)";v=(RegVal "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode") }
    @{ n="Visual Effects";       v=(RegVal "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "VisualFXSetting") }
)
foreach ($i in $info) {
    $val = if ($null -eq $i.v) { "ไม่ได้ตั้ง (ค่าเริ่มต้น)" } else { $i.v }
    "   {0,-24} = {1}" -f $i.n, $val | Write-Host -ForegroundColor Gray
}
$plan = (powercfg /getactivescheme) -replace '.*\(' -replace '\).*'
"   {0,-24} = {1}" -f "Power plan", $plan | Write-Host -ForegroundColor Gray

# ---------------------------------------------------------------- สรุป
Write-Host "`n===============================================================" -ForegroundColor Cyan
if ($todo.Count -eq 0) {
    Write-Host "  เครื่องนี้ไม่มีอะไรต้องแก้ เรียบร้อยดี" -ForegroundColor Green
    Write-Host "===============================================================" -ForegroundColor Cyan
    Read-Host "`nกด Enter เพื่อปิด"
    exit
}

Write-Host "  พบ $($todo.Count) จุดที่ควรแก้" -ForegroundColor Yellow
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host "`n[ สิ่งที่จะทำ ]" -ForegroundColor Yellow
if ($todo -contains "ss")      { Write-Host "  - ลบค่า 256/512 ของ Storage Sense (หยุดการล้าง Downloads)" -ForegroundColor White }
if ($todo -contains "task")    { foreach ($t in $foundTasks) { Write-Host "  - ถอนงานตั้งเวลา $t" -ForegroundColor White } }
if ($todo -contains "tune")    { Write-Host "  - ตั้ง Auto-Tuning เป็น normal" -ForegroundColor White }
if ($todo -contains "spooler") { Write-Host "  - ตั้ง Print Spooler กลับเป็น Automatic แล้วสตาร์ท" -ForegroundColor White }
if ($todo -contains "bg")      { Write-Host "  - เปิด Background Apps กลับ (คืนปุ่มลัด)" -ForegroundColor White }
Write-Host "`n  ไม่แตะไฟล์ส่วนตัว ไม่แตะค่าในหมวด 'ความชอบ' ข้างบน" -ForegroundColor DarkGray

$ans = Read-Host "`nแก้เลยไหม? (y/n) [n]"
if ($ans -ne 'y') {
    Write-Host "ยกเลิก ไม่ได้แก้อะไร" -ForegroundColor Yellow
    Read-Host "`nกด Enter เพื่อปิด"
    exit
}

Write-Host "`n[ กำลังแก้ ]" -ForegroundColor Cyan
if ($todo -contains "ss") {
    foreach ($v in "256","512") {
        try { Remove-ItemProperty -Path $ssPath -Name $v -ErrorAction Stop; Line "สำเร็จ" Green "ลบค่า Storage Sense '$v' แล้ว" }
        catch { Line "ข้าม" DarkGray "ค่า '$v' ไม่มีอยู่แล้ว" }
    }
}
if ($todo -contains "task") {
    foreach ($t in $foundTasks) {
        try { Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction Stop; Line "สำเร็จ" Green "ถอน $t แล้ว" }
        catch { Line "ผิดพลาด" Red "ถอน $t ไม่สำเร็จ: $($_.Exception.Message)" }
    }
}
if ($todo -contains "tune") {
    netsh int tcp set global autotuninglevel=normal | Out-Null
    Line "สำเร็จ" Green "ตั้ง Auto-Tuning เป็น normal แล้ว"
}
if ($todo -contains "spooler") {
    try {
        Set-Service -Name Spooler -StartupType Automatic -ErrorAction Stop
        Start-Service -Name Spooler -ErrorAction SilentlyContinue
        Line "สำเร็จ" Green "Spooler กลับเป็น Automatic และสตาร์ทแล้ว"
    } catch { Line "ผิดพลาด" Red "แก้ Spooler ไม่สำเร็จ: $($_.Exception.Message)" }
}
if ($todo -contains "bg") {
    try { Remove-ItemProperty -Path $bgPath -Name "GlobalUserDisabled" -ErrorAction Stop; Line "สำเร็จ" Green "เปิด Background Apps กลับแล้ว" }
    catch { Line "ผิดพลาด" Red "แก้ไม่สำเร็จ: $($_.Exception.Message)" }
}

# ---------------------------------------------------------------- ตรวจซ้ำ
Write-Host "`n===============================================================" -ForegroundColor Cyan
Write-Host "  ตรวจผลหลังแก้" -ForegroundColor Cyan
Write-Host "===============================================================" -ForegroundColor Cyan
$s2 = RegVal $ssPath "256"
if ($null -eq $s2 -or $s2 -eq 0) { Line "ok" Green "Storage Sense: ไม่มีสวิตช์ล้าง Downloads แล้ว" } else { Line "!!" Red "Storage Sense: ยังเหลือค่า 256 = $s2" }
$left = @(); foreach ($t in $taskName) { if (Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue) { $left += $t } }
if ($left.Count -eq 0) { Line "ok" Green "งานตั้งเวลา: ถอนออกหมดแล้ว" } else { Line "!!" Red "งานตั้งเวลา: ยังเหลือ $($left -join ', ')" }
$t2 = (((netsh interface tcp show global) | Select-String "Auto-Tuning Level").ToString() -split ':')[-1].Trim()
if ($t2 -eq 'normal') { Line "ok" Green "Auto-Tuning: normal" } else { Line "!!" Red "Auto-Tuning: $t2" }
$sp2 = Get-CimInstance Win32_Service -Filter "Name='Spooler'" -ErrorAction SilentlyContinue
Line "ok" Green "Spooler: $($sp2.StartMode) / $($sp2.State)"
$b2 = RegVal $bgPath "GlobalUserDisabled"
if ($b2 -ne 1) { Line "ok" Green "Background Apps: ไม่ได้ถูกปิด" } else { Line "!!" Red "Background Apps: ยังถูกปิดอยู่" }

Write-Host "`nเสร็จแล้ว ไม่ต้องรันซ้ำ" -ForegroundColor Green
Write-Host "หมายเหตุ: ถังขยะที่เคยถูกล้าง และ winsock ที่เคยถูกรีเซ็ต ย้อนกลับไม่ได้" -ForegroundColor DarkGray
Read-Host "`nกด Enter เพื่อปิด"
