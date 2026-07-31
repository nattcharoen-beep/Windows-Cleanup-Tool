# Windows Cleanup & Optimization Tool

A powerful, safe, and automated PowerShell script to clean up junk files, optimize system performance, and tweak Windows 10/11 for maximum speed and stability.

## Features

- **Clean System Junk**: Removes temporary files, prefetch, and unnecessary logs to free up disk space.
- **Optimize Memory**: Clears the Standby List to prevent micro-stuttering in games and heavy applications.
- **Network Optimization**: Tweaks DNS settings and Delivery Optimization for a faster internet experience.
- **Bloatware Removal**: Identifies and removes unwanted pre-installed applications safely.
- **Gaming & FPS Booster**: Enables Hardware-Accelerated GPU Scheduling (HAGS) and disables background GameDVR to maximize framerates and lower network ping.
- **Deep Browser Cleaner**: Aggressively clears cache and temporary data across Chrome, Edge, Brave, and Firefox to reclaim GBs of disk space.
- **Block Telemetry**: Shuts down background telemetry services and disables registry spying to reclaim system resources and protect privacy.
- **Preview Mode**: Simulates the cleanup process first, showing you exactly what will be removed before making any actual changes to your system.

## How to Use

1. Download or clone this repository.
2. Right-click on `Run_Cleanup_Tool.bat` and select **Run as Administrator**.
3. Follow the on-screen menu to select the modules you wish to run.
4. (Optional) Toggle Preview Mode using the `P` option to simulate changes before applying them.

## Safety First (Universal Edition)
This is the **Universal Edition**, which means **Preview Mode is enabled by default**. It is designed to be completely safe for any system. You must explicitly disable Preview Mode in the tool if you want to permanently delete files and apply system tweaks.

---
*Created for the community to keep Windows machines running fast and smooth!*


## ⚠️ Advanced Features (Version 1.1+)
These features are designed for deep system repair and extreme optimization. They are **not** included in the "Run All" (A) command and must be run individually. Please read carefully before using:
- **15. Repair System Deeply:** Runs SFC and DISM commands to automatically detect and repair corrupted Windows system files. Best used when encountering blue screens (BSOD) or system instability.
- **16. Reset Network Settings:** Flushes DNS and resets Winsock/TCP/IP configurations. Use this to fix internet connection drops, high ping, or corrupted network settings.
- **17. Unlock Ultimate Power Plan:** Unhides and activates the Windows "Ultimate Performance" power plan, ensuring maximum CPU utilization (Ideal for heavy gaming or rendering).
- **18. Clear Crash Dumps:** Deletes Windows Error Reporting (WER) archives, minidumps, and event logs. This reclaims space that is secretly taken up by crash histories.
- **19. Restore Classic Context Menu:** (Windows 11 Only) Reverts the simplified right-click menu back to the Windows 10 style, so you no longer have to click "Show more options".
- **20. Disable Ads & Tips:** Tweaks the registry to turn off annoying Windows tips, start menu suggestions, and lock screen ads.
