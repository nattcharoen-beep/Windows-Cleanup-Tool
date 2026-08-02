# Windows Cleanup & Optimization Tool — v1.1 (reviewed & fixed)

A PowerShell script that cleans junk files, optimizes system performance, and tweaks
Windows 10/11. This folder is a **reviewed and corrected copy** of `Version 1.1 advance function`.
The original folder is left untouched so you can compare or roll back.

## Read this first

This tool changes system settings, the registry, services, and scheduled tasks.
It is **not** "completely safe" in the sense that nothing can go wrong — that claim was
in the previous README and it was not accurate. What is true:

- **Preview Mode is ON by default.** Nothing is written or deleted until you turn it off with `P`.
- **Every destructive action now asks before it runs**, and defaults to "no".
- **Test on a machine you can restore first.** A VM snapshot or a fresh restore point.
- Some options need a **restart** to take effect.

## How to Use

1. Download or clone this repository.
2. Right-click `Run_Cleanup_Tool.bat` → **Run as Administrator**.
3. Pick a language, then pick a menu option.
4. Leave Preview Mode on for the first pass. Read what it says it will do, then decide.

## Menu

| # | What it does |
|---|---|
| 1 | Clean junk files (temp, prefetch, logs, browser cache) |
| 2 | SFC + DISM, and scan the registry for stale references |
| 3 | List startup programs and heavy services (report only) |
| 4 | Visual effects, power plan, page file, disk optimize, standby memory |
| 5 | Summary report |
| 6 | Security scan (Defender, hosts file, DNS, run keys, scheduled tasks) |
| 7 | Turn off background Cortana/tips/GameDVR/transparency |
| 8 | Analyze disk space (large folders, large files, possible duplicates) |
| 9 | Network: flush DNS/ARP, Delivery Optimization, auto-tuning, DNS servers |
| 10 | Set up weekly automatic maintenance tasks |
| 11 | Find and optionally remove bloatware |
| 12 | Gaming: HAGS, GameDVR off, Nagle's algorithm off |
| 13 | Deep browser cache cleaner |
| 14 | Block telemetry services |
| 15 | Deep system repair (SFC & DISM) |
| 16 | Reset network settings (Winsock & TCP/IP) |
| 17 | Unlock Ultimate Performance power plan |
| 18 | Clear crash dumps & event logs |
| 19 | Restore the classic Windows 11 right-click menu |
| 20 | Disable ads, tips & suggestions |
| **U** | **Remove the scheduled tasks that option 10 created** |
| A | Run All |
| P | Toggle Preview Mode |
| L | Back to language selection |
| Q | Exit |

### What "Run All" (A) does and does not do

Run All covers options **1, 2, 3, 4, 6, 7, 10, 11, 12, 13, 14** and then the report.

It deliberately does **not** include:
- **8 (Analyze Disk Space)** — it walks your drives and takes a long time.
- **9 (Optimize Network)** — it can reset the TCP/IP stack.
- **15–20 (Advanced)** — run those individually.

Run All still stops for input on options 6, 11 and 12, so it is not fully unattended.

## Things to know before you turn Preview Mode off

- **Options 4 and 17** set a high-performance power plan. On a laptop that means more heat
  and shorter battery life.
- **Option 12** turns on Hardware-Accelerated GPU Scheduling. If your GPU or driver
  reacts badly, turn it back off in Settings → Display → Graphics → Change default settings.
- **Option 18** clears **all** Windows event logs. That history is gone permanently and
  it is exactly what you would need to diagnose a crash later.
- **Options 12 and 19** write registry changes with no built-in undo. Option 7 does write
  a rollback script into `CleanupLogs\`.
- **Option 10** registers scheduled tasks that run as SYSTEM every week and stay on the
  machine even if you delete this tool. Use **option U** to remove them.

---

## Changes from `Version 1.1 advance function`

The original was reviewed line by line. It had no syntax errors, but the following
were found and fixed. Every fix was applied to **both** the English and Thai halves.

### Could destroy data

| Fix | Detail |
|---|---|
| **Storage Sense wrote the wrong registry values** | Option 10 wrote `30` to StoragePolicy value `256`, which is the switch that turns on **auto-deletion of your Downloads folder** — the opposite of what the comment claimed. Also `2048` (cadence) was set to `2`, which is not a valid value, and the Recycle Bin threshold went to `8` instead of `32`. Now sets only `2048=7` and `32=30`, and never touches `256`/`512`. |
| **Recycle Bin was emptied with no prompt** | `Clear-RecycleBin -Force` ran inside Run All. The Recycle Bin holds your own deleted files and this cannot be undone. Now asks, defaulting to no. |
| **Run All reset the network stack** | `netsh int ip reset` and `netsh winsock reset` ran unprompted, wiping static IPs, routes and VPN/proxy hooks. Now asks first, and option 9 was removed from Run All. |
| **Scheduled tasks could not be removed** | Option 10 registered `WeeklyTempCleanup` and `WeeklyRestorePoint` as SYSTEM with no uninstall path. Added menu option **U**. |
| **Registry cleanup deleted live uninstall entries** | Uninstall keys were deleted whenever `InstallLocation` did not resolve. Many installed programs record a stale `InstallLocation`, and deleting the key removes the only way to uninstall them. Now reports only. |

### Bugs

| Fix | Detail |
|---|---|
| **Thai half was missing the v1.1 fixes** | The English half had "disable Background Apps" and "disable Print Spooler" commented out — those were the v1.1 changes for Omen hotkeys and printing — but the **Thai half still ran both**. Anyone choosing Thai never got the v1.1 fixes. |
| **Wrong disk detected** | `Where-Object { $_.DeviceID -eq 0 -or $_.OperationalStatus -eq "OK" }` picked whichever disk reported OK first, so a machine with a second HDD could report "HDD" and then defrag the system SSD. Now resolves the disk behind the system volume. |
| **`$PatchCache$` path never worked** | Inside a double-quoted string it expanded to an empty variable, giving `C:\Windows\Installer\$\*`. Escaped. |
| **Visual effects tweak did nothing** | `VisualFXSetting = 3` means "Custom" and changes nothing on its own, but the script reported success. Now `2` (best performance). |
| **`\n` printed literally** | PowerShell uses a backtick, not a backslash. Two places. |
| **Elapsed time wrong past an hour** | Used `.Minutes` (the component) instead of `.TotalMinutes`. |
| **Rollback file was unusable** | `RegistryRestore_Part2.reg` contained PowerShell commands, not `.reg` content, so regedit rejected it, and every run appended to the same file. Now a timestamped `.ps1` per run. |
| **Disk analysis took hours** | Walked every drive and every user profile to full depth. Now depth-capped and skips `Windows`, `System Volume Information`, `$Recycle.Bin` and `AppData`. |
| **Bloatware uninstall was unreliable** | `-replace "/I","/X"` hit every `/I` in the string, and `UninstallString` was used as a `FilePath` even though it usually carries its own arguments. Now extracts the MSI product code, and for non-MSI uninstallers prints the command for you to run yourself. |
| **Telemetry set twice with opposite values** | Option 7 wrote `AllowTelemetry = 1`, option 14 wrote `0`. Run All did both. Option 7 no longer touches it. |

### Smaller

- Removed a duplicate UTF-8 BOM at the start of the file.
- Fixed menu typos: "เลือกราษา" → "เลือกภาษา", "ภาษาไทษ" → "ภาษาไทย".
- Thai half reported version `1.0`; now `1.1` like the English half.
- Menu prompt said "1-14" when there are 20 options; the working `L` option was never shown.
- `Run_Cleanup_Tool.bat` used codepage 874, which cannot render the box characters and
  emoji in the menus, and it was set only after elevation so Thai folder paths were mangled.
  Now UTF-8 (65001), set first.
- Removed a summary line claiming option 10 creates a desktop icon. It does not.

### Known issues not addressed

- The file still contains the **same code twice** (English and Thai), so every future
  change has to be made in two places. Merging them behind a message table would cut
  the file roughly in half and remove that risk.
- Options 15/16 duplicate what options 2/9 already do.
- Option 6's "suspicious program" check flags anything running from `AppData`, which
  includes Discord, Spotify and Teams. Expect false positives.
- Options 12 and 19 still have no undo.

---
*Reviewed and corrected copy. The original is in `Version 1.1 advance function`.*
