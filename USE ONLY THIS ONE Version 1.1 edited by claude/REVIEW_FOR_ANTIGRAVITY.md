# Code Review: cleanup_tool.ps1 v1.1

**ไฟล์ที่ตรวจ:** `Version 1.1 advance function/cleanup_tool.ps1` (3,950 บรรทัด)
**วันที่ตรวจ:** 2 สิงหาคม 2026
**ผลรวม:** 5 ปัญหาที่ทำข้อมูลผู้ใช้หายได้ · 11 บั๊ก · 9 จุดเล็ก · 1 ปัญหาโครงสร้าง

ทุกบรรทัดที่อ้างถึงเป็นเลขบรรทัดของไฟล์ต้นฉบับ v1.1

---

## สิ่งที่ทำได้ดีอยู่แล้ว

- ไม่มี syntax error (ตรวจด้วย `[Parser]::ParseFile`)
- `$Global:PreviewMode = $true` เป็นค่าเริ่มต้น — ตัดสินใจถูก
- มี `Test-SafePath` กันโฟลเดอร์ส่วนตัว
- มี `Create-RestorePoint`, มีระบบ log
- โครงสร้างแยกโมดูลอ่านง่าย คอมเมนต์ครบ

ปัญหาที่เจอไม่ได้อยู่ที่โครงสร้าง แต่อยู่ที่ **รายละเอียดของค่าที่เขียนลงระบบ** และ **การไม่ถามก่อนทำสิ่งที่ย้อนไม่ได้**

---

## 🔴 ระดับ 1 — ทำข้อมูลผู้ใช้หายได้จริง

### 1.1 Storage Sense — เขียน registry ผิด value name ทำให้เปิดสวิตช์ลบโฟลเดอร์ Downloads

**ตำแหน่ง:** บรรทัด 1530-1532 (และ 3493-3495 ฝั่งไทย) ใน `Setup-AutoMaintenance`

```powershell
Set-ItemProperty -Path $regPath -Name "2048" -Value 2 -Force # Run weekly
Set-ItemProperty -Path $regPath -Name "256" -Value 30 -Force # Delete Temp older than 30
Set-ItemProperty -Path $regPath -Name "8" -Value 30 -Force   # Delete Recycle Bin older than 30
```

**ปัญหา:** value name ผิดทั้ง 3 ตัว ภายใต้
`HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy`

| value | ความหมายจริง | โค้ดเขียน | ผลที่เกิด |
|---|---|---|---|
| `2048` | cadence — รับเฉพาะ `0/1/7/30` | `2` | ค่าไม่ถูกต้อง Windows ไม่รับ |
| `256` | **สวิตช์เปิดการล้างโฟลเดอร์ Downloads** | `30` | **เปิดสวิตช์ลบ Downloads** |
| `512` | เกณฑ์วันของ Downloads | ไม่ได้เขียน | — |
| `8` | สวิตช์เปิดล้าง Recycle Bin | `30` | เปิดสวิตช์ |
| `32` | เกณฑ์วันของ Recycle Bin | ไม่ได้เขียน | — |

คอมเมนต์เขียนว่า "Delete Temp older than 30" แต่ค่าที่เขียนลงไปคือสวิตช์ Downloads
**ขัดกับที่ README ประกาศว่า "explicitly avoids touching any user personal files"**

ตรวจบนเครื่องจริงที่เคยรันเวอร์ชันนี้ พบค่าค้างอยู่จริง: `2048=2`, `256=30`, `8=30`, `512=0`
(รอดเพราะ `512=0` แปลว่า Never — แต่เป็นความบังเอิญ ไม่ใช่การออกแบบ)

**แก้เป็น:**
```powershell
Set-ItemProperty -Path $regPath -Name "2048" -Value 7 -Force  # run weekly
Set-ItemProperty -Path $regPath -Name "32" -Value 30 -Force   # Recycle Bin: 30 days
# ไม่แตะ 256 / 512 เด็ดขาด — เป็นโฟลเดอร์ไฟล์ส่วนตัวของผู้ใช้
```

---

### 1.2 `Clear-RecycleBin -Force` ไม่ถาม และอยู่ใน Run All

**ตำแหน่ง:** บรรทัด 371 (และ 2333) ใน `Clean-SystemJunk`

```powershell
if ($Global:PreviewMode -eq $false) {
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
```

ถังขยะคือไฟล์ส่วนตัวที่ผู้ใช้ยังไม่ตัดสินใจลบถาวร ล้างแล้วกู้ไม่ได้
`Test-SafePath` ไม่ครอบคลุมจุดนี้ และ `Clean-SystemJunk` อยู่ใน `Run All` → กด `A` ครั้งเดียวถังขยะหาย

**แก้:** ใส่ `Read-Host` ยืนยัน default = ไม่ล้าง

---

### 1.3 Run All รีเซ็ต network stack โดยไม่ถาม

**ตำแหน่ง:** บรรทัด 1450-1451 (และ 3413-3414) ใน `Optimize-Network`
`Optimize-Network` ถูกเรียกจาก `'A'` ที่บรรทัด 1938

```powershell
netsh int ip reset | Out-Null
netsh winsock reset | Out-Null
```

ล้าง static IP, route table และ LSP ของ VPN/proxy ต้อง reboot และผู้ใช้กู้เองไม่ได้ถ้าไม่ได้จดค่าไว้
ผู้ใช้ที่กด `A` โดยไม่รู้ตัวอาจเน็ตใช้ไม่ได้หลังรีสตาร์ท

**แก้:** ใส่ prompt ยืนยัน + ถอด `Optimize-Network` ออกจาก Run All

---

### 1.4 Scheduled Task ฝังถาวร ไม่มีทางถอน

**ตำแหน่ง:** บรรทัด 1517-1519, 1561-1563

```powershell
Register-ScheduledTask -TaskName "WeeklyTempCleanup" -Action $action -Trigger $trigger `
    -Description "Loves System Clean" -User "System" -RunLevel Highest -Force
```

สร้าง task รันเป็น SYSTEM ทุกสัปดาห์ **ตลอดไป** และยังอยู่แม้ผู้ใช้ลบเครื่องมือทิ้ง
ในโปรแกรมไม่มีเมนูถอน ผู้ใช้ทั่วไปไม่รู้ว่าต้องเข้า Task Scheduler ไปลบเอง

**แก้:** เพิ่มเมนู undo ที่เรียก `Unregister-ScheduledTask` และแจ้งผู้ใช้ตอนสร้างว่าถอนยังไง

---

### 1.5 `Repair-Registry` ลบคีย์ Uninstall ของโปรแกรมที่ยังติดตั้งอยู่

**ตำแหน่ง:** บรรทัด 578-591 (และ 2540-2553)

```powershell
if (-not [string]::IsNullOrWhiteSpace($installLocation)) {
    if (-not (Test-Path -Path $installLocation -ErrorAction SilentlyContinue)) {
        if ($Global:PreviewMode -eq $false) {
            if ($key.PSChildName -notmatch "^KB\d+" -and $key.PSChildName -notmatch "^\{[\w-]+\}$") {
                Remove-Item -Path $key.PSPath -Recurse -Force -ErrorAction SilentlyContinue
```

โปรแกรมจำนวนมากเขียน `InstallLocation` ไม่ตรง/ตกค้าง ทั้งที่ยังติดตั้งอยู่จริง
ลบคีย์ = ผู้ใช้ถอนโปรแกรมนั้นผ่าน Settings/Control Panel ไม่ได้อีกเลย และไม่มี backup

**แก้:** เปลี่ยนเป็นรายงานอย่างเดียว ไม่ลบ

---

## 🟠 ระดับ 2 — บั๊กที่ทำให้ฟีเจอร์ไม่ทำงานหรือทำงานผิด

### 2.1 ตรวจชนิดดิสก์ผิด → เสี่ยง defrag ใส่ SSD
**บรรทัด 836**
```powershell
$diskInfo = Get-PhysicalDisk | Where-Object { $_.DeviceID -eq 0 -or $_.OperationalStatus -eq "OK" } |
            Select-Object -First 1 -Property MediaType
```
`-or` ทำให้หยิบดิสก์ลูกไหนก็ได้ที่สถานะ OK ไม่ใช่ดิสก์ที่ระบบอยู่
เครื่องที่มี HDD ลูกที่สอง → ได้ `MediaType = HDD` → สั่ง `Optimize-Volume -DriveLetter C -Defrag` ลงบน SSD

**แก้:** `Get-Partition -DriveLetter $sysDriveLetter | Get-Disk | Get-PhysicalDisk`

### 2.2 `$PatchCache$` ถูกตีความเป็นตัวแปร
**บรรทัด 312** — ใน double-quoted string `$PatchCache` = ตัวแปรว่าง
ได้ path จริง `C:\Windows\Installer\$\*` → โมดูลนี้ไม่เคยล้างอะไรได้เลยตั้งแต่แรก
**แก้:** escape ด้วย backtick หรือใช้ single quote

### 2.3 Visual Effects ปรับแล้วไม่มีผล แต่รายงานว่าสำเร็จ
**บรรทัด 776** — `VisualFXSetting = 3` คือ "Custom" ไม่ได้เปลี่ยนอะไรเอง
ต้องเขียน `UserPreferencesMask` ประกอบด้วย ถึงจะมีผล
**แก้:** ใช้ `2` (Adjust for best performance)

### 2.4 `\n` ไม่ใช่ escape ของ PowerShell
**บรรทัด 1756, 3720** — `Write-Host "\nRunning..."` พิมพ์ `\n` ออกมาตรง ๆ
**แก้:** ใช้ backtick-n

### 2.5 เวลาที่ใช้ในรายงานเพี้ยนถ้าเกิน 1 ชั่วโมง
**บรรทัด 1019** — `$($timeTaken.Minutes)` คือ component ไม่ใช่ยอดรวม
รัน 1 ชม. 5 นาที → รายงาน "5 นาที" (เกิดได้จริงเพราะ `Analyze-DiskSpace` ช้ามาก)
**แก้:** `[int]$timeTaken.TotalMinutes`

### 2.6 ไฟล์ rollback ใช้กู้ไม่ได้
**บรรทัด 1175, 1202-1204**
```powershell
$restoreFile = "$Global:LogDir\RegistryRestore_Part2.reg"
...
$restoreCmd = "if (!(Test-Path '$Path')) { New-Item ... }; Set-ItemProperty ..."
Add-Content -Path $restoreFile -Value $restoreCmd
```
เนื้อในเป็นคำสั่ง PowerShell แต่ตั้งนามสกุล `.reg` → ดับเบิลคลิกแล้ว regedit error
และ `Add-Content` ต่อท้ายไฟล์เดิมทุกรอบ ทำให้ค่าจากหลายรอบปนกัน

ตรวจไฟล์จริงที่เครื่องผู้ใช้: ค่าที่บันทึกไว้เป็นค่า**หลัง**ถูกแก้แล้ว (เพราะถูกเขียนตอนรันรอบที่ 2)
→ ใช้กู้ค่าดั้งเดิมไม่ได้เลย

**แก้:** ตั้งนามสกุล `.ps1` + ใส่ timestamp ในชื่อไฟล์ แยกไฟล์ต่อรอบ

### 2.7 `Analyze-DiskSpace` ช้าจนใช้งานจริงไม่ได้ และอยู่ใน Run All
**บรรทัด 1346** — `Get-ChildItem -Path "$drv\" -File -Recurse` ทุกไดรฟ์ ไม่จำกัดความลึก
**บรรทัด 1360** — `Get-ChildItem -Path "C:\Users\" -File -Recurse` ทุกโปรไฟล์
กินเวลาเป็นชั่วโมงและกิน RAM สูง
**แก้:** ใส่ `-Depth`, ข้าม `Windows` / `System Volume Information` / `$Recycle.Bin` / `AppData`, ถอดออกจาก Run All

### 2.8 `Remove-Bloatware` ประกอบคำสั่งถอนแบบไม่ปลอดภัย
**บรรทัด 1619, 1624**
```powershell
$uninstallArgs = $uninstallString -replace "msiexec.exe", "" -replace "/I", "/X"
...
Start-Process $uninstallString -ArgumentList "/S", "/quiet" -Wait -NoNewWindow
```
- `-replace "/I","/X"` แทนที่ทุกตำแหน่งในสตริง ไม่ใช่เฉพาะสวิตช์ (เช่น path ที่มี `/I` อยู่)
- `$uninstallString` มัก**มี argument ติดมาด้วย** จึงใช้เป็น `-FilePath` ไม่ได้
- การยัด `/S` ใส่ uninstaller ที่ไม่รู้จัก ทำให้เกิดพฤติกรรมที่คาดเดาไม่ได้

**แก้:** ดึง MSI product code ด้วย regex แล้วประกอบคำสั่งใหม่ · ถ้าไม่ใช่ MSI ให้แสดงคำสั่งให้ผู้ใช้รันเอง

### 2.9 Telemetry ตั้งค่าขัดกันเองใน Run All
**บรรทัด 1225** เมนู 7 → `AllowTelemetry = 1`
**บรรทัด 1736** เมนู 14 → `AllowTelemetry = 0`
Run All รันทั้งคู่ ผลจริงได้ `0` แต่เมนู 7 บอกผู้ใช้ว่าตั้งเป็น "ระดับพื้นฐาน"
**แก้:** ให้เหลือแหล่งความจริงเดียว

### 2.10 ⚠️ ฝั่งไทยไม่ได้รับ fix ของ v1.1 เลย
**นี่คือบั๊กที่ร้ายแรงที่สุดในหมวดนี้ เพราะทำให้ release note ของ v1.1 ไม่จริง**

commit ของ v1.1 เขียนว่า *"restore Omen Hotkeys, keep Printer Spooler active"*
แต่แก้แค่ฝั่งอังกฤษ:

| | ฝั่ง EN | ฝั่ง TH |
|---|---|---|
| ปิด Background Apps (`GlobalUserDisabled`) | comment ไว้ (บรรทัด 1218-1220) | **ยังทำงานอยู่** (บรรทัด 3180-3182) |
| ปิด Print Spooler | comment ไว้ (บรรทัด 1268-1271) | **ยังทำงานอยู่** (บรรทัด 3230-3234) |

ผู้ใช้ที่เลือกภาษาไทย = ไม่ได้ fix ของ v1.1 เลยแม้แต่ข้อเดียว
ตรวจ log บนเครื่องจริงพบว่า Spooler เคยถูกตั้งเป็น Manual จริง

---

## 🟡 ระดับ 3 — จุดเล็ก

| จุด | ตำแหน่ง | รายละเอียด |
|---|---|---|
| BOM ซ้ำ 2 ตัว | byte 0-5 | `ef bb bf ef bb bf` — parser ผ่านแต่ผิด ควรเหลือตัวเดียว |
| สะกดผิด | 3935 | "เลือก**ราษา**" → "เลือกภาษา" |
| สะกดผิด | 3938 | "ภาษาไท**ษ**" → "ภาษาไทย" |
| version ไม่ตรง | 1996 | ฝั่งไทยตั้ง `'1.0'` ฝั่งอังกฤษ `'1.1'` |
| prompt ผิดช่วง | 1902, 3863 | บอก "1-14" ทั้งที่มีถึง 20 |
| เมนูซ่อน | 1948, 3909 | ตัวเลือก `L` ทำงานได้แต่ไม่แสดงในเมนู และสองภาษาเขียนไม่ตรงกัน |
| codepage ผิด | `Run_Cleanup_Tool.bat:21` | `chcp 874` เรนเดอร์ `╔═╗`, `█`, 🧹 ไม่ได้ · และตั้งหลัง elevation ทำให้ path ภาษาไทยเพี้ยน → ควรใช้ `chcp 65001` ตั้งแต่บรรทัดแรก |
| dead code | 82, 2044 | `Write-Banner` ไม่เคยถูกเรียก |
| ข้อความไม่จริง | 3537 | สรุปบอกว่า "สร้างไอคอนบนหน้าจอ" แต่ไม่มีโค้ดส่วนนั้น |
| false positive สูง | 1120 | `-match "Temp\|AppData\|Roaming"` → Discord/Spotify/Teams เข้าเงื่อนไขหมด แจ้งเตือนผู้ใช้เกินจำเป็น |
| เมนูซ้ำซ้อน | 15/16 vs 2/9 | SFC+DISM และ network reset ทำงานเดิมซ้ำสองที่ |
| `Read-Host` กลาง Run All | เมนู 6, 8, 9, 11 | ทำให้ "Run All" รันทิ้งไว้ไม่ได้ |

---

## ⭐ ปัญหาโครงสร้าง — ต้นเหตุของข้อ 2.10

ไฟล์มีโค้ดชุดเดียวกัน **ซ้ำ 2 ชุด**
- `Run-EnglishMode` บรรทัด 1-1961
- `Run-ThaiMode` บรรทัด 1963-3922

ต่างกันแค่ข้อความ ส่วนตรรกะเหมือนกันทุกบรรทัด (ตรวจยืนยันด้วย diff แล้ว)

**ผลเสียที่เกิดขึ้นจริงแล้ว:** ข้อ 2.10 — แก้ที่เดียว ลืมอีกที่ ทำให้ผู้ใช้ครึ่งหนึ่งไม่ได้ fix

**ข้อเสนอ:** รวมเป็นชุดเดียว แล้วแยกข้อความเป็น hashtable ตามภาษา

```powershell
$Msg = @{
    en = @{ CleanJunk = "Clean junk files"; Confirm = "Are you sure? (y/n)" }
    th = @{ CleanJunk = "ทำความสะอาดไฟล์ขยะ"; Confirm = "ยืนยันหรือไม่? (y/n)" }
}
$L = $Msg[$lang]
Write-Host $L.CleanJunk
```

จะลดไฟล์จาก 3,950 เหลือประมาณ 2,000 บรรทัด และตัดปัญหา "แก้ที่เดียวลืมอีกที่" ถาวร

---

## หลักการที่แนะนำให้ยึด

1. **ทุกอย่างที่ย้อนไม่ได้ ต้องถามก่อน และ default = ไม่ทำ**
   ถังขยะ · event log · registry key · network reset

2. **ทุกอย่างที่ฝังถาวร ต้องมีทางถอน**
   scheduled task ที่สร้างแล้วถอนไม่ได้ คือกับดัก

3. **"Run All" ต้องไม่รวมสิ่งที่ทั้งช้ามากและเสี่ยงมาก**
   ผู้ใช้กด A เพราะไม่อยากอ่าน — จึงต้องปลอดภัยเป็นพิเศษ

4. **README ต้องตรงกับสิ่งที่โค้ดทำจริง**
   v1.1 เขียนว่า "completely safe" และ "avoids touching any user personal files"
   ขณะที่โค้ดล้างถังขยะและเปิดสวิตช์ลบ Downloads

5. **ก่อนเขียนค่าลง registry ให้ยืนยัน value name กับเอกสาร Microsoft ก่อนเสมอ**
   ข้อ 1.1 เกิดจากการเดา value name แล้วเขียนคอมเมนต์ตามที่เดา

---

## วิธีตรวจว่าแก้แล้วใช้ได้จริง

```powershell
# 1. ตรวจ syntax โดยไม่ต้องรัน
$e = $null
[System.Management.Automation.Language.Parser]::ParseFile("cleanup_tool.ps1", [ref]$null, [ref]$e)
$e

# 2. ตรวจว่าสองภาษาไม่หลุดกัน — บรรทัดคำสั่งที่แก้ระบบต้องเหมือนกันเป๊ะ
#    (ถ้ายังไม่รวมโค้ด ต้องทำ diff ทุกครั้งหลังแก้)
```

3. ทดสอบใน Preview Mode ก่อนเสมอ ดู log ใน `CleanupLogs\`
4. ทดสอบจริงบน VM ที่มี snapshot เท่านั้น ห้ามทดสอบครั้งแรกบนเครื่องใช้งานจริง
5. หลังรันเมนู 10 → เปิด Settings → System → Storage → Storage Sense
   ต้องเห็นว่า "Delete files in my Downloads folder" **ยังปิดอยู่**

---

## สรุป

โครงและแนวคิดดี ปัญหาอยู่ที่รายละเอียดที่ตรวจสอบไม่ครบ 3 เรื่อง:

1. **เดา registry value name แล้วไม่ได้ยืนยันกับเอกสาร** → 1.1
2. **ไม่ได้แยกว่าอะไรย้อนได้ อะไรย้อนไม่ได้** → 1.2, 1.3, 1.4, 1.5
3. **โค้ดซ้ำสองชุด ทำให้ fix หลุด** → 2.10

ข้อ 3 คือข้อที่ควรแก้ก่อน เพราะถ้าไม่แก้ ทุก fix ในอนาคตมีโอกาสหลุดครึ่งหนึ่งเสมอ

โค้ดที่แก้แล้วทั้งหมดอยู่ใน `Version 1.1 edited by claude/`
รายละเอียดการแก้แต่ละจุดอยู่ในหัวข้อ "Changes from Version 1.1 advance function" ของ `README.md` ในโฟลเดอร์นั้น
