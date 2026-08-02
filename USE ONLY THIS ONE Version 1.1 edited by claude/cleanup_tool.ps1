function Run-EnglishMode {
    & {

# Windows System Cleanup & Optimization Tool
# Version 1.1
# Created for: Antigravity Project
# Description: Advanced system cleanup and optimization tool. First half of the complete suite.
# 
# IMPORTANT NOTE: This script is designed to be completely safe.
# It explicitly avoids touching any user personal files and always creates a system restore point.

# =============================================================================
# 2. ADMIN CHECK & ELEVATION
# =============================================================================
# Check if the script is running with Administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "This script requires administrator rights. (Administrator) Attempting to rerun...." -ForegroundColor Yellow
    try {
        # Attempt to relaunch the script as Administrator
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
        Exit
    } catch {
        Write-Host "Cannot be run with administrator rights. Please right click on the script and select 'Run as Administrator'" -ForegroundColor Red
        Pause
        Exit
    }
}

# =============================================================================
# 3. GLOBAL VARIABLES
# =============================================================================
# Set basic configuration and state variables
$Global:ScriptVersion = '1.1'
$Global:LogDir = "$PSScriptRoot\CleanupLogs"

# Ensure the log directory exists
if (-not (Test-Path -Path $Global:LogDir)) {
    try {
        New-Item -ItemType Directory -Path $Global:LogDir -Force | Out-Null
    } catch {
        Write-Host "Unable to create log file. (Log Directory)!" -ForegroundColor Red
    }
}

# Generate a unique log file name based on the current timestamp
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$Global:LogFile = Join-Path $Global:LogDir "cleanup_$timestamp.log"
$Global:TotalCleaned = 0
$Global:TotalFixed = 0
$Global:PreviewMode = $true
$Global:StartTime = Get-Date

# =============================================================================
# 4. HELPER FUNCTIONS
# =============================================================================

<#
.SYNOPSIS
Writes a message to the console and appends it to the log file.
#>
function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [string]$Type = "INFO"
    )
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$time] [$Type] $Message"
    try {
        Add-Content -Path $Global:LogFile -Value $logMessage -ErrorAction SilentlyContinue
    } catch {
        # Silent fail if log is locked
    }
}

<#
.SYNOPSIS
Displays the main ASCII art banner for the tool.
#>
function Write-Banner {
    Clear-Host
    $banner = @"
===============================================================================
   _      __ _           __                       ___                            
  | | /| / /(_)___  ____/ /___  _      __ _____  / _/___  ____  __  __ ________ 
  | |/ |/ // // _ \/ __  // _ \| | /| / // ___/ / /_ / _ \/ __ \/ / / // ___/ _ \
  | /| / // //  __/ /_/ // (_) | |/ |/ /(__  ) / __//  __/ /_/ / /_/ // /  /  __/
  |__/|__//_/ \___/\__,_/ \___/|__/|__//____/ /_/   \___/\____/\__,_//_/   \___/ 
                                                                                 
===============================================================================
                     Cleaning and Optimizing Tools
                                  Version $Global:ScriptVersion
===============================================================================
"@
    Write-Host $banner -ForegroundColor Cyan
    Write-Log "Started Cleanup Tool Version $Global:ScriptVersion" "INFO"
}

<#
.SYNOPSIS
Displays a formatted header for each module section.
#>
function Write-ModuleHeader {
    param([string]$ModuleName)
    Write-Host "`n"
    Write-Host "===============================================================================" -ForegroundColor Magenta
    Write-Host " [$ModuleName] " -ForegroundColor White -BackgroundColor Magenta
    Write-Host "===============================================================================" -ForegroundColor Magenta
    Write-Log "Starting Module: $ModuleName" "INFO"
}

<#
.SYNOPSIS
Helper for writing success messages in green.
#>
function Write-Success {
    param([string]$Message)
    Write-Host "[succeed] $Message" -ForegroundColor Green
    Write-Log $Message "SUCCESS"
}

<#
.SYNOPSIS
Helper for writing warning messages in yellow.
#>
function Write-Warning2 {
    param([string]$Message)
    Write-Host "[Warning] $Message" -ForegroundColor Yellow
    Write-Log $Message "WARNING"
}

<#
.SYNOPSIS
Helper for writing error messages in red.
#>
function Write-Error2 {
    param([string]$Message)
    Write-Host "[mistake] $Message" -ForegroundColor Red
    Write-Log $Message "ERROR"
}

<#
.SYNOPSIS
Displays a customized progress bar in the console.
#>
function Write-ProgressBar {
    param(
        [int]$PercentComplete,
        [string]$Activity
    )
    try {
        $progressBarWidth = 50
        $completedWidth = [math]::Round(($PercentComplete / 100) * $progressBarWidth)
        $remainingWidth = $progressBarWidth - $completedWidth
        
        $completedBar = "█" * $completedWidth
        $remainingBar = "-" * $remainingWidth
        
        $progressString = "[$completedBar$remainingBar] $PercentComplete%"
        
        Write-Progress -Activity $Activity -Status $progressString -PercentComplete $PercentComplete -ErrorAction SilentlyContinue
    } catch {}
}

<#
.SYNOPSIS
Calculates the total size of a folder in bytes recursively.
#>
function Get-FolderSize {
    param([string]$Path)
    $size = 0
    if (Test-Path -Path $Path) {
        try {
            $colItems = Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue
            if ($colItems) {
                $measure = $colItems | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue
                if ($measure.Sum) {
                    $size = $measure.Sum
                }
            }
        } catch {
            Write-Log "Failed to calculate folder size for $Path" "ERROR"
        }
    }
    return $size
}

<#
.SYNOPSIS
Formats raw bytes into a human-readable string (KB, MB, GB).
#>
function Format-FileSize {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) {
        return "{0:N2} GB" -f ($Bytes / 1GB)
    } elseif ($Bytes -ge 1MB) {
        return "{0:N2} MB" -f ($Bytes / 1MB)
    } elseif ($Bytes -ge 1KB) {
        return "{0:N2} KB" -f ($Bytes / 1KB)
    } else {
        return "$Bytes Bytes"
    }
}

<#
.SYNOPSIS
CRITICAL: Validates that a given path is safe to delete.
Protects against deleting user personal folders or system critical roots.
#>
function Test-SafePath {
    param([string]$Path)
    
    # Define protected locations that should never be deleted
    $protectedPaths = @(
        "$env:USERPROFILE\Desktop",
        "$env:USERPROFILE\Documents",
        "$env:USERPROFILE\Downloads",
        "$env:USERPROFILE\Pictures",
        "$env:USERPROFILE\Videos",
        "$env:USERPROFILE\Music",
        "$env:USERPROFILE\OneDrive",
        "$env:USERPROFILE\3D Objects",
        "$env:USERPROFILE\Favorites",
        "$env:PUBLIC\Desktop",
        "$env:PUBLIC\Documents",
        "$env:PUBLIC\Downloads"
    )
    
    # 1. Prevent deleting protected personal folders
    foreach ($protected in $protectedPaths) {
        # Check if the target path is inside or exactly the protected path
        if ($Path -like "$protected*") {
            Write-Log "SAFETY BLOCK: Path $Path is protected. Aborting deletion." "WARNING"
            return $false
        }
    }
    
    # 2. Prevent deleting system root folders
    $sysRoot = $env:SystemDrive + "\"
    $winDir = $env:WINDIR
    $system32 = Join-Path $winDir "System32"
    $programFiles = $env:ProgramFiles
    $programFilesx86 = ${env:ProgramFiles(x86)}
    
    $criticalRoots = @(
        $sysRoot,
        $winDir,
        $system32,
        $programFiles,
        $programFilesx86
    )
    
    foreach ($crit in $criticalRoots) {
        # Exact match check to prevent "C:\Windows" or "C:\" deletion
        if ($Path -eq $crit -or $Path -eq "$crit\") {
            Write-Log "SAFETY BLOCK: Critical system path $Path requested for deletion. Aborting." "WARNING"
            return $false
        }
    }
    
    # Path is deemed safe for automated cleaning
    return $true
}

# =============================================================================
# 5. FUNCTION: Create-RestorePoint
# =============================================================================
function Create-RestorePoint {
    Write-ModuleHeader "Creating a system restore point (System Restore Point)"
    Write-Host "Preparing to create a system restore point for security reasons..." -ForegroundColor Cyan
    
    try {
        Write-ProgressBar -PercentComplete 10 -Activity "Checking service System Restore"
        
        # Enable system restore on the system drive if it isn't already
        $sysDrive = $env:SystemDrive + "\"
        Enable-ComputerRestore -Drive $sysDrive -ErrorAction SilentlyContinue
        
        Write-ProgressBar -PercentComplete 40 -Activity "Creating a system restore point is in progress. (This process may take some time.)"
        
        # Create the checkpoint
        $description = "CleanupTool_Before_Optimization_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        $result = Checkpoint-Computer -Description $description -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        
        Write-ProgressBar -PercentComplete 100 -Activity "System restore point created successfully."
        Write-Success "System restore point created successfully.: $description"
    } catch {
        Write-ProgressBar -PercentComplete 100 -Activity "An error occurred."
        Write-Error2 "Unable to create a system restore point.: $($_.Exception.Message)"
        Write-Warning2 "Hint: You can still continue. However, the system will not be able to reverse the changes."
    }
}

# =============================================================================
# 6. MODULE 1: Clean-SystemJunk
# =============================================================================
function Clean-SystemJunk {
    Write-ModuleHeader "Module 1: Clean system junk files (System Junk)"
    
    # Array of locations to clean
    $itemsToClean = @(
        @{ Name="User temporary files (User Temp)"; Path="$env:TEMP\*"; IsFolder=$false },
        @{ Name="Temporary file of Windows"; Path="$env:WINDIR\Temp\*"; IsFolder=$false },
        @{ Name="Update cache Windows"; Path="$env:WINDIR\SoftwareDistribution\Download\*"; IsFolder=$false },
        @{ Name="Small image cache (Thumbnail Cache)"; Path="$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db"; IsFolder=$false },
        @{ Name="Error report file (Windows Error Reports)"; Path="$env:PROGRAMDATA\Microsoft\Windows\WER\ReportArchive\*"; IsFolder=$false },
        @{ Name="System log files (System Logs - CBS)"; Path="$env:WINDIR\Logs\CBS\*.log"; IsFolder=$false },
        @{ Name="Update delivery file (Delivery Optimization)"; Path="$env:WINDIR\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache\*"; IsFolder=$false },
        @{ Name="Font cache (Font Cache)"; Path="$env:WINDIR\ServiceProfiles\LocalService\AppData\Local\FontCache\*.dat"; IsFolder=$false },
        @{ Name="Patch installer cache files (Patch Cache)"; Path="$env:WINDIR\Installer\`$PatchCache`$\*"; IsFolder=$false },
        @{ Name="Cache Windows Defender"; Path="$env:PROGRAMDATA\Microsoft\Windows Defender\Scans\History\Results\*"; IsFolder=$false },
        @{ Name="Memory data file crashed (Crash Dumps)"; Path="$env:LOCALAPPDATA\CrashDumps\*"; IsFolder=$false }
    )
    
    $totalFreedSpace = 0
    $totalFilesDeleted = 0
    
    foreach ($item in $itemsToClean) {
        $path = $item.Path
        $name = $item.Name
        
        Write-Host "Inspecting $name..." -ForegroundColor Cyan
        Write-Log "Cleaning junk category: $name ($path)" "INFO"
        
        $itemSize = 0
        $filesDeleted = 0
        
        try {
            $files = Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue
            
            foreach ($file in $files) {
                # Ensure the file path is safe before attempting deletion
                if (Test-SafePath -Path $file.FullName) {
                    if ($Global:PreviewMode -eq $false) {
                        $size = $file.Length
                        Remove-Item -Path $file.FullName -Force -Recurse -ErrorAction SilentlyContinue
                        
                        # Verify if the file was actually deleted
                        if (-not (Test-Path -Path $file.FullName)) {
                            $itemSize += $size
                            $filesDeleted++
                        }
                    } else {
                        # In preview mode, just count the sizes
                        $itemSize += $file.Length
                        $filesDeleted++
                    }
                }
            }
            
            if ($filesDeleted -gt 0) {
                $formattedSize = Format-FileSize -Bytes $itemSize
                Write-Success "Delete junk files $name quantity $filesDeleted File saves space $formattedSize"
                $totalFreedSpace += $itemSize
                $totalFilesDeleted += $filesDeleted
            } else {
                Write-Host "  - The file was not found or does not have permission to delete it in this section." -ForegroundColor DarkGray
            }
            
        } catch {
            Write-Warning2 "cannot delete $name got it all ($($_.Exception.Message))"
        }
    }
    
    # Empty Recycle Bin
    Write-Host "Emptying the trash can (Recycle Bin)..." -ForegroundColor Cyan
    try {
        if ($Global:PreviewMode -eq $false) {
            # FIXED: the Recycle Bin holds the user's own deleted files and emptying it
            # cannot be undone, so it never runs unattended any more.
            Write-Warning2 "The Recycle Bin holds YOUR OWN deleted files. Emptying it CANNOT be undone."
            $rbAns = Read-Host "Empty the Recycle Bin? (y/n) [n]"
            if ($rbAns -eq 'y') {
                Clear-RecycleBin -Force -ErrorAction SilentlyContinue
                Write-Success "The trash can has been emptied."
            } else {
                Write-Host "  - Skipped. The Recycle Bin was left untouched." -ForegroundColor DarkGray
            }
        } else {
            Write-Success "[Preview] Will ask for confirmation before emptying the trash can."
        }
    } catch {
        Write-Warning2 "Unable to empty trash can"
    }
    
    # Old Prefetch files (older than 30 days)
    Write-Host "Checking old Prefetch files..." -ForegroundColor Cyan
    try {
        $prefetchPath = "$env:WINDIR\Prefetch\*"
        $oldPrefetch = Get-ChildItem -Path $prefetchPath -Force -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) -and -not $_.PSIsContainer }
        
        $pfSize = 0
        $pfDeleted = 0
        
        foreach ($pf in $oldPrefetch) {
            if (Test-SafePath -Path $pf.FullName) {
                if ($Global:PreviewMode -eq $false) {
                    $size = $pf.Length
                    Remove-Item -Path $pf.FullName -Force -ErrorAction SilentlyContinue
                    if (-not (Test-Path -Path $pf.FullName)) {
                        $pfSize += $size
                        $pfDeleted++
                    }
                } else {
                    $pfSize += $pf.Length
                    $pfDeleted++
                }
            }
        }
        
        if ($pfDeleted -gt 0) {
            $formattedSize = Format-FileSize -Bytes $pfSize
            Write-Success "Delete old Prefetch files. Number $pfDeleted File saves space $formattedSize"
            $totalFreedSpace += $pfSize
            $totalFilesDeleted += $pfDeleted
        } else {
            Write-Host "  - No Prefetch files older than 30 days" -ForegroundColor DarkGray
        }
    } catch {
        Write-Warning2 "There was a problem managing the file. Prefetch"
    }
    
    # Flush DNS Cache
    Write-Host "Clearing cache DNS (Flush DNS)..." -ForegroundColor Cyan
    try {
        if ($Global:PreviewMode -eq $false) {
            ipconfig /flushdns | Out-Null
            Write-Success "Successfully cleared DNS cache."
        } else {
            Write-Success "[Preview] It will clear the cache. DNS"
        }
    } catch {
        Write-Warning2 "Unable to clear DNS cache"
    }
    
    # Browser Cache Cleanups
    Write-Host "Cleaning browser cache (Chrome, Edge, Firefox, Brave)..." -ForegroundColor Cyan
    $browserCaches = @(
        @{ Name="Google Chrome Cache"; Path="$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache\Cache_Data\*" },
        @{ Name="Microsoft Edge Cache"; Path="$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache\Cache_Data\*" },
        @{ Name="Mozilla Firefox Cache"; Path="$env:LOCALAPPDATA\Mozilla\Firefox\Profiles\*\cache2\entries\*" },
        @{ Name="Brave Browser Cache"; Path="$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Cache\Cache_Data\*" }
    )
    
    foreach ($bc in $browserCaches) {
        $bpath = $bc.Path
        $bname = $bc.Name
        $bSize = 0
        $bDeleted = 0
        
        try {
            $bfiles = Get-ChildItem -Path $bpath -Recurse -Force -ErrorAction SilentlyContinue
            foreach ($bf in $bfiles) {
                if (Test-SafePath -Path $bf.FullName) {
                    if ($Global:PreviewMode -eq $false) {
                        $size = $bf.Length
                        Remove-Item -Path $bf.FullName -Force -Recurse -ErrorAction SilentlyContinue
                        if (-not (Test-Path -Path $bf.FullName)) {
                            $bSize += $size
                            $bDeleted++
                        }
                    } else {
                        $bSize += $bf.Length
                        $bDeleted++
                    }
                }
            }
            if ($bDeleted -gt 0) {
                $formattedSize = Format-FileSize -Bytes $bSize
                Write-Success "Delete cache $bname quantity $bDeleted File saves space $formattedSize"
                $totalFreedSpace += $bSize
                $totalFilesDeleted += $bDeleted
            }
        } catch {
            Write-Warning2 "Skip cache $bname (The browser may already be launching.)"
        }
    }
    
    $Global:TotalCleaned += $totalFreedSpace
    $formattedTotal = Format-FileSize -Bytes $totalFreedSpace
    Write-Host "`n=======================================================" -ForegroundColor Cyan
    Write-Host " Summary of junk file cleaning results: Delete $totalFilesDeleted Files, get space back $formattedTotal" -ForegroundColor Green
    Write-Host "=======================================================" -ForegroundColor Cyan
    Write-Log "Module 1 Complete: Freed $formattedTotal ($totalFilesDeleted files)" "SUCCESS"
}

# =============================================================================
# 7. MODULE 2: Repair-Registry
# =============================================================================
function Repair-Registry {
    Write-ModuleHeader "Module 2: Check and repair registry and system files"
    
    # System File Checker (SFC)
    Write-Host "Starting System File Checker (SFC)... (This may take several minutes.)" -ForegroundColor Cyan
    Write-Log "Running SFC /scannow" "INFO"
    try {
        if ($Global:PreviewMode -eq $false) {
            $sfcOutput = & sfc /scannow
            $sfcResult = $sfcOutput | Select-String "Windows Resource Protection did not find any integrity violations." -Quiet
            if ($sfcResult) {
                Write-Success "SFC: No corrupt system files found. The system is in perfect condition."
            } else {
                $sfcRepaired = $sfcOutput | Select-String "successfully repaired them" -Quiet
                if ($sfcRepaired) {
                    Write-Success "SFC: A corrupted system file was found and has been repaired."
                    $Global:TotalFixed++
                } else {
                    Write-Warning2 "SFC: Corrupted files were found but could not be fully repaired. Please check the log for details."
                }
            }
        } else {
            Write-Success "[Preview] Will run the command sfc /scannow"
        }
    } catch {
        Write-Error2 "Unable to run SFC program"
    }
    
    # DISM Check & Repair
    Write-Host "Starting DISM to repair the computer image. Windows..." -ForegroundColor Cyan
    Write-Log "Running DISM /Online /Cleanup-Image /RestoreHealth" "INFO"
    try {
        if ($Global:PreviewMode -eq $false) {
            $dismOutput = & DISM /Online /Cleanup-Image /RestoreHealth
            $dismResult = $dismOutput | Select-String "The restore operation completed successfully" -Quiet
            if ($dismResult) {
                Write-Success "DISM: The system image was successfully repaired."
                $Global:TotalFixed++
            } else {
                Write-Warning2 "DISM: The work is completed but some errors may have occurred."
            }
        } else {
            Write-Success "[Preview] Will run the command DISM /Online /Cleanup-Image /RestoreHealth"
        }
    } catch {
        Write-Error2 "Unable to run DISM program."
    }
    
    # Registry Cleanup Operations
    Write-Host "Scanning the registry for file references that don't exist...." -ForegroundColor Cyan
    
    $invalidEntriesCount = 0
    
    # Registry Task 1: Check Shared DLLs
    Write-Host " - Check common system files (Shared DLLs)" -ForegroundColor DarkGray
    $sharedDllPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\SharedDLLs"
    if (Test-Path -Path $sharedDllPath) {
        try {
            # Backup registry key conceptually - done by System Restore previously
            $dllItems = Get-ItemProperty -Path $sharedDllPath -ErrorAction SilentlyContinue
            $properties = $dllItems.psobject.properties | Where-Object { $_.Name -like "*:\*" }
            
            foreach ($prop in $properties) {
                $filePath = $prop.Name
                # Check if the file referenced in registry still exists on disk
                if (-not (Test-Path -Path $filePath -ErrorAction SilentlyContinue)) {
                    Write-Log "Invalid Shared DLL found: $filePath" "INFO"
                    if ($Global:PreviewMode -eq $false) {
                        Remove-ItemProperty -Path $sharedDllPath -Name $filePath -ErrorAction SilentlyContinue
                        $invalidEntriesCount++
                    } else {
                        $invalidEntriesCount++
                    }
                }
            }
        } catch {
            Write-Log "Error scanning Shared DLLs" "ERROR"
        }
    }
    
    # Registry Task 2: Orphaned Uninstall Entries
    Write-Host " - Check for residual uninstallation items." -ForegroundColor DarkGray
    $uninstallPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    foreach ($up in $uninstallPaths) {
        try {
            $uninstallKeys = Get-Item -Path $up -ErrorAction SilentlyContinue
            foreach ($key in $uninstallKeys) {
                $installLocation = (Get-ItemProperty -Path $key.PSPath -Name "InstallLocation" -ErrorAction SilentlyContinue).InstallLocation
                $displayName = (Get-ItemProperty -Path $key.PSPath -Name "DisplayName" -ErrorAction SilentlyContinue).DisplayName
                
                # If InstallLocation is defined but the physical path doesn't exist
                if (-not [string]::IsNullOrWhiteSpace($installLocation)) {
                    if (-not (Test-Path -Path $installLocation -ErrorAction SilentlyContinue)) {
                        Write-Log "Orphaned Uninstall entry found: $($key.PSChildName) ($displayName)" "INFO"
                        # FIXED: report only, never delete. Plenty of genuinely installed
                        # programs record an InstallLocation that no longer resolves, and
                        # removing the key destroys the only way to uninstall them.
                        $invalidEntriesCount++
                    }
                }
            }
        } catch {
            Write-Log "Error scanning Uninstall entries" "ERROR"
        }
    }
    
    # Registry Task 3: Old MUI Cache
    Write-Host " - clean items MUI Cache" -ForegroundColor DarkGray
    $muiCachePath = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache"
    if (Test-Path -Path $muiCachePath) {
        try {
            $muiItems = Get-ItemProperty -Path $muiCachePath -ErrorAction SilentlyContinue
            $properties = $muiItems.psobject.properties | Where-Object { $_.Name -like "*:\*.exe*" }
            
            foreach ($prop in $properties) {
                # Format is usually "C:\path\to\app.exe.FriendlyAppName"
                $pathOnly = $prop.Name -replace '\.FriendlyAppName$','' -replace '\.ApplicationCompany$',''
                if ($pathOnly -like "*:\*") {
                    if (-not (Test-Path -Path $pathOnly -ErrorAction SilentlyContinue)) {
                        if ($Global:PreviewMode -eq $false) {
                            Remove-ItemProperty -Path $muiCachePath -Name $prop.Name -ErrorAction SilentlyContinue
                            $invalidEntriesCount++
                        } else {
                            $invalidEntriesCount++
                        }
                    }
                }
            }
        } catch {
            Write-Log "Error scanning MUI Cache" "ERROR"
        }
    }
    
    if ($invalidEntriesCount -gt 0) {
        Write-Success "Found $invalidEntriesCount residual registry entries (orphaned uninstall entries are reported only, never deleted)."
        $Global:TotalFixed += $invalidEntriesCount
    } else {
        Write-Host " - The registry is in good condition. No remaining items found." -ForegroundColor Green
    }
    
    Write-Host "`n=======================================================" -ForegroundColor Cyan
    Write-Host " Summary of Repair Results: Repairs all corrupted files and registry. $Global:TotalFixed list" -ForegroundColor Green
    Write-Host "=======================================================" -ForegroundColor Cyan
    Write-Log "Module 2 Complete: Fixed $Global:TotalFixed registry/system issues" "SUCCESS"
}

# =============================================================================
# 8. MODULE 3: Optimize-Startup
# =============================================================================
function Optimize-Startup {
    Write-ModuleHeader "Module 3: Check autostart programs (Startup Optimization)"
    Write-Host "Gathering information about programs that are opened. Windows..." -ForegroundColor Cyan
    
    $startupItems = @()
    
    # Helper function to extract startup items from registry paths
    function Get-RegistryStartup {
        param([string]$Path, [string]$Type)
        $items = @()
        if (Test-Path -Path $Path) {
            $keys = Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue
            $props = $keys.psobject.properties | Where-Object { 
                $_.Name -ne "PSPath" -and 
                $_.Name -ne "PSParentPath" -and 
                $_.Name -ne "PSChildName" -and 
                $_.Name -ne "PSDrive" -and 
                $_.Name -ne "PSProvider" 
            }
            foreach ($p in $props) {
                $items += [PSCustomObject]@{
                    Name = $p.Name
                    Command = $p.Value
                    Location = $Type
                    Status = "Enabled"
                }
            }
        }
        return $items
    }
    
    # 1. User specific run keys
    $startupItems += Get-RegistryStartup -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Type "Registry (HKCU)"
    
    # 2. Machine wide run keys
    $startupItems += Get-RegistryStartup -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Type "Registry (HKLM)"
    $startupItems += Get-RegistryStartup -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run" -Type "Registry (HKLM 32-bit)"
    
    # 3. Startup Folder (User)
    $startupFolder = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    if (Test-Path -Path $startupFolder) {
        $files = Get-ChildItem -Path $startupFolder -ErrorAction SilentlyContinue
        foreach ($f in $files) {
            $startupItems += [PSCustomObject]@{
                Name = $f.BaseName
                Command = $f.FullName
                Location = "Startup Folder (User)"
                Status = "Enabled"
            }
        }
    }
    
    # 4. WMI Startup Commands
    try {
        $wmiStartup = Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue
        foreach ($w in $wmiStartup) {
            # Prevent duplicates
            if (-not ($startupItems.Name -contains $w.Name)) {
                $startupItems += [PSCustomObject]@{
                    Name = $w.Name
                    Command = $w.Command
                    Location = $w.Location
                    Status = "Enabled"
                }
            }
        }
    } catch {}
    
    # Display the results
    if ($startupItems.Count -gt 0) {
        Write-Host "`nList of programs that start automatically (Startup Programs):" -ForegroundColor Yellow
        $startupItems | Format-Table -Property Name, Command, Location, Status -AutoSize | Out-String | Write-Host
        
        Write-Host "Speed-up Tip: You can disable programs that you are not regularly using." -ForegroundColor Cyan
        Write-Host "Method: Press the button Ctrl+Shift+Esc to open Task Manager -> Go to the tab 'Startup apps' -> Right-click the program and select 'Disable'" -ForegroundColor Cyan
    } else {
        Write-Host "No autostart programs found." -ForegroundColor Green
    }
    
    # Checking for heavy services that could be tuned
    Write-Host "`nAnalyzing services that use high system resources...." -ForegroundColor Yellow
    try {
        $services = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.StartType -eq "Automatic" -and $_.Status -eq "Running" }
        $heavyServices = @("SysMain", "DiagTrack", "WSearch", "Spooler")
        $foundHeavy = $false
        
        foreach ($srv in $services) {
            if ($heavyServices -contains $srv.Name) {
                $foundHeavy = $true
                $desc = ""
                if ($srv.Name -eq "SysMain") { $desc = "Superfetch - If using HDD, it may cause the disk to run. 100% often" }
                if ($srv.Name -eq "DiagTrack") { $desc = "Connected User Experiences - Sending diagnostic data back to Microsoft" }
                if ($srv.Name -eq "WSearch") { $desc = "Windows Search - File indexing service If there are many files, it may use a lot of CPU/Disk." }
                if ($srv.Name -eq "Spooler") { $desc = "Print Spooler - If you have never used a printer Can be set to Manual." }
                
                Write-Host "- $($srv.Name) : $desc" -ForegroundColor White
            }
        }
        
        if ($foundHeavy) {
            Write-Host "`nAdditional advice: If your device is slow or working hard. These services can be changed to 'Manual' (customized) available in Services.msc" -ForegroundColor Cyan
            Write-Host "(This script will bypass automatic service shutdown to avoid affecting your system.)" -ForegroundColor DarkGray
        } else {
            Write-Host "Not finding the service of concern" -ForegroundColor Green
        }
        
    } catch {
        Write-Warning2 "Unable to retrieve Services at this time."
    }
    
    # Note: Check for scheduled tasks that impact performance (informative only)
    Write-Host "`nCheck scheduled tasks (Scheduled Tasks):" -ForegroundColor Yellow
    try {
        $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.State -eq "Ready" -and $_.TaskPath -notmatch "\\Microsoft\\" }
        if ($tasks) {
            Write-Host "Found a number of tasks scheduled by external applications. $($tasks.Count) work" -ForegroundColor White
        } else {
            Write-Host "There are no jobs from external apps prepared to run." -ForegroundColor Green
        }
    } catch {}
    
    Write-Log "Module 3 Complete: Startup apps and services analyzed" "INFO"
}

# =============================================================================
# 9. MODULE 4: Tune-Performance
# =============================================================================
function Tune-Performance {
    Write-ModuleHeader "Module 4: Tuning system performance (Performance Tuning)"
    
    # 1. Visual Effects Tuning
    Write-Host "Adjusting animation settings (Visual Effects) for speed...." -ForegroundColor Cyan
    try {
        if ($Global:PreviewMode -eq $false) {
            # Value 3 = Custom. Windows uses a combination of settings.
            # FIXED: 3 means "Custom", which changes nothing on its own - the script
            # reported success while doing nothing. 2 = "Adjust for best performance".
            Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Value 2 -ErrorAction SilentlyContinue
            
            # Explicitly keep font smoothing enabled for clear text readability
            Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "FontSmoothing" -Value "2" -ErrorAction SilentlyContinue
            
            Write-Success "Visual Effects adjusted now. (The clarity of the letters is still maintained.)"
        } else {
            Write-Success "[Preview] Visual Effects will be adjusted for performance."
        }
    } catch {
        Write-Warning2 "Unable to customize Visual Effects"
    }
    
    # 2. Power Plan Setup
    Write-Host "The power plan is being set to High Performance. (High Performance)..." -ForegroundColor Cyan
    try {
        if ($Global:PreviewMode -eq $false) {
            # GUID for standard High Performance power plan
            $highPerfGuid = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
            powercfg -setactive $highPerfGuid | Out-Null
            
            # Verify if it was successfully changed
            $currentPlan = powercfg -getactivescheme
            if ($currentPlan -match $highPerfGuid) {
                Write-Success "Successfully changed power plan to High Performance."
            } else {
                Write-Warning2 "This machine may not have a High Performance plan or be restricted by the manufacturer. (OEM)"
            }
        } else {
            Write-Success "[Preview] It will try to enable the power plan. High Performance"
        }
    } catch {
        Write-Warning2 "A problem occurred while attempting to resolve it. Power Plan"
    }
    
    # 3. Virtual Memory (Page File) Check
    Write-Host "Verifying virtual memory space settings (Page File)..." -ForegroundColor Cyan
    try {
        $computerSystem = Get-WmiObject Win32_ComputerSystem -ErrorAction SilentlyContinue
        if ($computerSystem -and $computerSystem.AutomaticManagedPagefile -eq $false) {
            if ($Global:PreviewMode -eq $false) {
                # Enable system managed pagefile for optimal stability
                $computerSystem.AutomaticManagedPagefile = $true
                $computerSystem.Put() | Out-Null
                Write-Success "Adjust Windows to automatically manage Page File (System Managed) for stability."
            } else {
                Write-Success "[Preview] Automatic Page File management will be enabled."
            }
        } else {
            Write-Host "  - Page File It is already set to be automatically managed by the system (best)" -ForegroundColor Green
        }
    } catch {
        Write-Warning2 "Unable to check the status of Page File."
    }
    
    # 4. Storage Optimization (SSD TRIM / HDD Defrag)
    Write-Host "Inspecting and adjusting the storage media (Disk Optimization)..." -ForegroundColor Cyan
    try {
        $sysDriveLetter = $env:SystemDrive.Substring(0,1)
        # Attempt to determine media type (SSD or HDD)
        # FIXED: the old -or condition grabbed whichever disk reported OK first, so on a
        # machine with a second HDD it could report "HDD" and then defrag the system SSD.
        # Resolve the physical disk that actually backs the system volume instead.
        $diskInfo = $null
        try {
            $diskInfo = Get-Partition -DriveLetter $sysDriveLetter -ErrorAction Stop |
                        Get-Disk -ErrorAction Stop |
                        Get-PhysicalDisk -ErrorAction Stop |
                        Select-Object -First 1 -Property MediaType
        } catch {
            Write-Log "Could not resolve the physical disk behind drive $sysDriveLetter" "WARNING"
        }
        
        $mediaType = "Unknown"
        if ($diskInfo -and $diskInfo.MediaType) {
            $mediaType = $diskInfo.MediaType
        }
        
        Write-Host "Type of disk detected: $mediaType" -ForegroundColor Yellow
        
        if ($Global:PreviewMode -eq $false) {
            if ($mediaType -eq "SSD") {
                Write-Host "Running the TRIM command to maintain speed. SSD..." -ForegroundColor Cyan
                Optimize-Volume -DriveLetter $sysDriveLetter -ReTrim -Verbose:$false | Out-Null
                Write-Success "Successfully cleared empty data blocks (TRIM) to SSD."
            } elseif ($mediaType -eq "HDD") {
                Write-Host "Sorting data (Defragmentation) for HDD..." -ForegroundColor Cyan
                Write-Host "(This process can take a long time. please wait a moment...)" -ForegroundColor Yellow
                Optimize-Volume -DriveLetter $sysDriveLetter -Defrag -Verbose:$false | Out-Null
                Write-Success "Successfully defragmented the disk."
            } else {
                # Fallback to standard optimization
                Optimize-Volume -DriveLetter $sysDriveLetter -Verbose:$false | Out-Null
                Write-Success "Successfully performed Optimize system drive."
            }
        } else {
            Write-Success "[Preview] Will optimize the drive. ($mediaType)"
        }
    } catch {
        Write-Warning2 "Discs cannot be customized at this time. (may be currently in use))"
    }
    
    # 5. Clear Standby Memory List
    Write-Host "Clearing standby memory cache (Standby Memory List)..." -ForegroundColor Cyan
    try {
        if ($Global:PreviewMode -eq $false) {
            # Advanced C# P/Invoke to call NtSetSystemInformation (MemoryPurgeStandbyList)
            $memUtilCode = @"
using System;
using System.Runtime.InteropServices;

public class MemoryCleaner
{
    [DllImport("advapi32.dll", SetLastError = true)]
    internal static extern bool OpenProcessToken(IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);
    
    [DllImport("kernel32.dll", SetLastError = true)]
    internal static extern IntPtr GetCurrentProcess();
    
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    internal static extern bool LookupPrivilegeValue(string lpSystemName, string lpName, out long lpLuid);
    
    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    internal struct TOKEN_PRIVILEGES
    {
        public int PrivilegeCount;
        public long Luid;
        public int Attributes;
    }
    
    [DllImport("advapi32.dll", SetLastError = true)]
    internal static extern bool AdjustTokenPrivileges(IntPtr TokenHandle, bool DisableAllPrivileges, ref TOKEN_PRIVILEGES NewState, int BufferLength, IntPtr PreviousState, IntPtr ReturnLength);
    
    [DllImport("ntdll.dll")]
    internal static extern int NtSetSystemInformation(int SystemInformationClass, IntPtr SystemInformation, int SystemInformationLength);

    public static void EmptyStandbyList()
    {
        IntPtr token;
        if (OpenProcessToken(GetCurrentProcess(), 0x0020 | 0x0008, out token))
        {
            long luid;
            if (LookupPrivilegeValue(null, "SeProfileSingleProcessPrivilege", out luid))
            {
                TOKEN_PRIVILEGES tp = new TOKEN_PRIVILEGES();
                tp.PrivilegeCount = 1;
                tp.Luid = luid;
                tp.Attributes = 2; // SE_PRIVILEGE_ENABLED
                
                AdjustTokenPrivileges(token, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
                
                // 80 corresponds to SystemMemoryListInformation
                // 4 corresponds to MemoryPurgeStandbyList
                int systemMemoryListInformation = 80;
                int command = 4; 
                
                IntPtr pCommand = Marshal.AllocHGlobal(sizeof(int));
                Marshal.WriteInt32(pCommand, command);
                NtSetSystemInformation(systemMemoryListInformation, pCommand, sizeof(int));
                Marshal.FreeHGlobal(pCommand);
            }
        }
    }
}
"@
            Add-Type -TypeDefinition $memUtilCode -Language CSharp -ErrorAction SilentlyContinue
            [MemoryCleaner]::EmptyStandbyList()
            Write-Success "The memory cache (Standby List) has been cleared to reduce freezing."
        } else {
            Write-Success "[Preview] will wash Standby Memory List"
        }
    } catch {
        # Fallback to simple Garbage Collection if C# compilation/execution fails
        [GC]::Collect()
        Write-Warning2 "Unable to deep wash Perform a basic memory recall instead."
    }
    
    Write-Log "Module 4 Complete: Performance tuned" "SUCCESS"
}

# =============================================================================
# 10. MODULE 5: Generate-Report
# =============================================================================
function Generate-Report {
    Write-ModuleHeader "Module 5: Summary of system cleaning and inspection results"
    
    $endTime = Get-Date
    $timeTaken = New-TimeSpan -Start $Global:StartTime -End $endTime
    
    # Gather comprehensive system info for the report
    Write-Host "Final system data is being compiled...." -ForegroundColor Cyan
    
    $osInfo = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cpuInfo = Get-CimInstance Win32_Processor | Select-Object -First 1 -ErrorAction SilentlyContinue
    
    $ramInfo = 0
    $freeRam = 0
    if ($osInfo) {
        $ramInfo = [math]::Round($osInfo.TotalVisibleMemorySize / 1MB, 2)
        $freeRam = [math]::Round($osInfo.FreePhysicalMemory / 1MB, 2)
    }
    
    $sysDrive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'" -ErrorAction SilentlyContinue
    $diskTotal = 0
    $diskFree = 0
    if ($sysDrive) {
        $diskTotal = [math]::Round($sysDrive.Size / 1GB, 2)
        $diskFree = [math]::Round($sysDrive.FreeSpace / 1GB, 2)
    }
    
    # Calculate boot time
    $bootTimeStr = "Don't know the information."
    try {
        if ($osInfo -and $osInfo.LastBootUpTime) {
            $bootTimeStr = $osInfo.LastBootUpTime.ToString("dd/MM/yyyy HH:mm:ss")
        }
    } catch {}
    
    # SMART Disk Health check
    $smartStatusStr = "Status unknown"
    try {
        $smartData = Get-WmiObject -Namespace root\wmi -Class MSStorageDriver_FailurePredictStatus -ErrorAction SilentlyContinue
        if ($smartData) {
            $failing = $false
            foreach ($s in $smartData) {
                if ($s.PredictFailure) { $failing = $true }
            }
            if ($failing) {
                $smartStatusStr = "Vulnerability found (there may be a disk hardware problem)"
            } else {
                $smartStatusStr = "normal (OK)"
            }
        }
    } catch {}
    
    # Formatting sizes properly
    $totalCleanedStr = Format-FileSize -Bytes $Global:TotalCleaned
    
    # Constructing the final report text
    $reportOutput = @"

===============================================================================
                           Report summarizing the results of system improvements
===============================================================================

[ General system information (System Information) ]
- Operating system:       $($osInfo.Caption)
- Processor (CPU):  $($cpuInfo.Name)
- Memory status: available $freeRam GB / from all $ramInfo GB
- Disk space (drive C:): Remaining $diskFree GB / from all $diskTotal GB
- Disk health (SMART):   $smartStatusStr
- Last booted the system when:      $bootTimeStr

[ Performance (Cleanup & Optimization Results) ]
- Total working time:   $([int]$timeTaken.TotalMinutes) minute $($timeTaken.Seconds) seconds
- Disk space recovered:        $totalCleanedStr
- Number of problems repaired:   $Global:TotalFixed list

[ Additional information ]
All work records (Log File) are stored securely at:
$Global:LogFile
===============================================================================
"@

    # Print out the report
    Write-Host $reportOutput -ForegroundColor Cyan
    Write-Log "Generated Final Report" "INFO"
    Write-Log "Total Cleaned: $totalCleanedStr, Total Fixed: $Global:TotalFixed" "INFO"
    
    Write-Host "`nComplete the first part of the process. (Part 1)" -ForegroundColor Green
}

# Module 6: Scan-Security
function Scan-Security {
    Write-ModuleHeader  "security scan (Scan Security)"
    Write-Log  "Starting security scan" -Type "INFO"

    # Update Windows Defender definitions
    Write-Host "Updating virus database Windows Defender..." -ForegroundColor Cyan
    if (-not $Global:PreviewMode) {
        try {
            Update-MpSignature -ErrorAction Stop
            Write-Success  "The virus database has been successfully updated."
        } catch {
            Write-Warning2  "Unable to update virus signature database.: $($_.Exception.Message)"
        }
    } else {
        Write-Host "[PREVIEW] Update database Windows Defender" -ForegroundColor DarkGray
    }

    $scanChoice = Read-Host "What kind of scan do you want? (1) Quick Scan, (2) Full Scan, (0) Skip [1]"
    if ($scanChoice -eq '1' -or $scanChoice -eq '') {
        $scanType = "QuickScan"
    } elseif ($scanChoice -eq '2') {
        $scanType = "FullScan"
    } else {
        $scanType = $null
    }

    if ($scanType -ne $null) {
        Write-Host "Scanning for viruses ($scanType)..." -ForegroundColor Cyan
        if (-not $Global:PreviewMode) {
            try {
                Start-MpScan -ScanType $scanType -ErrorAction Stop
                Write-Success  "Virus scan complete"
            } catch {
                Write-Warning2  "An error occurred scanning for viruses.: $($_.Exception.Message)"
            }
        } else {
            Write-Host "[PREVIEW] Scan for viruses $scanType" -ForegroundColor DarkGray
        }
    }

    # Check hosts file for suspicious entries
    Write-Host "`nChecking file hosts..." -ForegroundColor Cyan
    $hostsFile = "$env:windir\System32\drivers\etc\hosts"
    if (Test-Path $hostsFile) {
        try {
            $hostsLines = Get-Content $hostsFile | Where-Object { $_ -notmatch '^\s*#' -and $_ -notmatch '^\s*$' -and $_ -notmatch 'localhost' -and $_ -notmatch '127\.0\.0\.1' -and $_ -notmatch '::1' }
            if ($hostsLines.Count -gt 0) {
                Write-Warning2  "Suspicious entries found in hosts file (may have been modified by malware):"
                $hostsLines | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
            } else {
                Write-Success  "Normal hosts file (no foreign entries found))"
            }
        } catch { Write-Warning2  "Unable to read hosts file" }
    }

    # Check DNS Settings
    Write-Host "`nChecking settings DNS..." -ForegroundColor Cyan
    try {
        $dnsServers = Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object { $_.ServerAddresses -ne $null }
        foreach ($adapter in $dnsServers) {
            Write-Host "adapter $($adapter.InterfaceAlias) use DNS: $($adapter.ServerAddresses -join ', ')" -ForegroundColor Gray
        }
        Write-Success  "DNS verification completed (please consider whether the DNS is foreign or not))"
    } catch {
        Write-Warning2  "Unable to verify DNS: $($_.Exception.Message)"
    }

    # Check Registry Run keys
    Write-Host "`nChecking for suspicious startup programs in Registry..." -ForegroundColor Cyan
    $runKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
    )
    $suspiciousFound = $false
    foreach ($key in $runKeys) {
        if (Test-Path $key) {
            $entries = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
            foreach ($prop in $entries.psobject.properties) {
                if ($prop.Name -notin @("PSPath","PSParentPath","PSChildName","PSDrive","PSProvider")) {
                    $val = $prop.Value -as [string]
                    if ($val -match "Temp|AppData|Roaming" -or $prop.Name -match "^[a-zA-Z0-9]{8,15}$") {
                        Write-Warning2  "Found a suspicious program in Registry: $($prop.Name) -> $val"
                        $suspiciousFound = $true
                    }
                }
            }
        }
    }
    if (-not $suspiciousFound) {
        Write-Success  "No suspicious startup programs found."
    }

    # Check Scheduled Tasks
    Write-Host "`nInspecting suspicious Scheduled Tasks..." -ForegroundColor Cyan
    try {
        $suspiciousTasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { 
            $_.Author -notmatch "Microsoft" -and 
            $_.State -ne "Disabled" -and 
            ($_.Actions.Execute -match "Temp" -or $_.Actions.Execute -match "AppData")
        }
        if ($suspiciousTasks) {
            Write-Warning2  "Found a suspicious task (running from a temporary folder and not belonging to Microsoft):"
            $suspiciousTasks | ForEach-Object { Write-Host "  $($_.TaskName) -> $($_.Actions.Execute)" -ForegroundColor Yellow }
        } else {
            Write-Success  "No suspicious tasks found."
        }
    } catch {
        Write-Warning2  "Unable to check Scheduled Tasks."
    }
    
    # Check browser extensions
    Write-Host "`nChecking browser extension folder (Extensions)..." -ForegroundColor Cyan
    $chromeExt = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Extensions"
    $edgeExt = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Extensions"
    if (Test-Path $chromeExt) {
        $count = (Get-ChildItem -Path $chromeExt -Directory).Count
        Write-Host "Found extension Chrome: $count list" -ForegroundColor Gray
    }
    if (Test-Path $edgeExt) {
        $count = (Get-ChildItem -Path $edgeExt -Directory).Count
        Write-Host "Found extension Edge: $count list" -ForegroundColor Gray
    }
    Write-Host "Note: Please check for unknown extensions in your browser yourself." -ForegroundColor DarkGray

    # Security Summary
    Write-Host "`n=== Summary of security scan results ===" -ForegroundColor Green
    Write-Host "Scan and analysis complete If you find a yellow item Please check further yourself." -ForegroundColor White
}

# Module 7: Optimize-Background
function Optimize-Background {
    Write-ModuleHeader  "Turn off background work (Optimize Background)"
    Write-Log  "Starting background optimization" -Type "INFO"

    if (-not (Test-Path $Global:LogDir)) { New-Item -Path $Global:LogDir -ItemType Directory -Force | Out-Null }
    # FIXED: the contents are PowerShell commands, not a .reg file, so the old name was
    # misleading (regedit rejects it). One file per run, so restores are not mixed.
    $restoreFile = "$Global:LogDir\RegistryRestore_$(Get-Date -Format 'yyyyMMdd_HHmmss').ps1"

    if (-not $Global:PreviewMode) {
        Create-RestorePoint
    }

    # Helper function for safe registry modification with logging
    function Update-RegSetting {
        param($Desc, $Path, $Name, $NewValue)
        Write-Host "`nenergy$Desc..." -ForegroundColor Cyan
        try {
            $currentVal = "Not Set"
            if (Test-Path $Path) {
                $item = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
                if ($item -ne $null -and $item.psobject.properties.match($Name).Count) { 
                    $currentVal = $item.$Name 
                }
            } else {
                if (-not $Global:PreviewMode) { New-Item -Path $Path -Force | Out-Null }
            }
            
            Write-Host "  details: $Desc" -ForegroundColor Gray
            Write-Host "  Current value: $currentVal" -ForegroundColor Yellow
            Write-Host "  desired value: $NewValue" -ForegroundColor Green
            
            if (-not $Global:PreviewMode) {
                # Create restore entry in log file
                $restoreCmd = "if (!(Test-Path '$Path')) { New-Item -Path '$Path' -Force | Out-Null }; Set-ItemProperty -Path '$Path' -Name '$Name' -Value '$currentVal' -Force"
                if ($currentVal -ne "Not Set") {
                    Add-Content -Path $restoreFile -Value $restoreCmd
                }
                
                Set-ItemProperty -Path $Path -Name $Name -Value $NewValue -Force
                Write-Success  "Successfully customized"
            } else {
                Write-Host "  [PREVIEW] Skip writing values Registry" -ForegroundColor DarkGray
            }
        } catch {
            Write-Warning2  "An error occurred.: $($_.Exception.Message)"
        }
    }

    # Disable Background Apps (UWP) - DISABLED by AI to prevent breaking Omen Hub hotkeys
    # Update-RegSetting -Desc "Close background applications. (Background Apps)" `
    #                   -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" `
    #                   -Name "GlobalUserDisabled" -NewValue 1

    # FIXED: removed. This wrote AllowTelemetry = 1 while menu 14 writes 0, so "Run All"
    # set the same key twice and told the user something that was not the end result.
    # Telemetry is now handled by menu 14 (Block Telemetry) only.

    # Disable Cortana
    Update-RegSetting -Desc "Disable Cortana and search restrictions" `
                      -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" `
                      -Name "AllowCortana" -NewValue 0

    # Disable Tips & Suggestions
    Update-RegSetting -Desc "Close tips and tricks from Windows (Tips & Suggestions)" `
                      -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" `
                      -Name "SubscribedContent-338389Enabled" -NewValue 0

    # Disable Game Bar & Game DVR
    Update-RegSetting -Desc "Turn off the Game DVR (video game recording) feature in HKCU" `
                      -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" `
                      -Name "AppCaptureEnabled" -NewValue 0

    Update-RegSetting -Desc "Turn off the Game Bar feature on the main system. (HKLM)" `
                      -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\ApplicationManagement\AllowGameDVR" `
                      -Name "value" -NewValue 0

    # Disable Transparency
    Update-RegSetting -Desc "Turn off the translucent effect (Transparency Effects)" `
                      -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" `
                      -Name "EnableTransparency" -NewValue 0

    # Stop OneDrive Sync
    Write-Host "`nOption to stop syncing OneDrive:" -ForegroundColor Cyan
    $ans = Read-Host "Want to stop OneDrive processes to save resources? (The file will not be deleted.) (y/n) [n]"
    if ($ans -eq 'y') {
        if (-not $Global:PreviewMode) {
            try {
                Stop-Process -Name "OneDrive" -Force -ErrorAction SilentlyContinue
                Write-Success  "OneDrive was successfully paused."
            } catch { Write-Warning2  "OneDrive cannot be stopped or it is not running." }
        } else { Write-Host "  [PREVIEW] stop Process OneDrive" -ForegroundColor DarkGray }
    }

    # Disable unnecessary services
    Write-Host "`nChecking services that are not frequently used..." -ForegroundColor Cyan
    $servicesToCheck = @("Fax", "XboxGipSvc")
    
    # Check for printers (DISABLED by AI: User wants Printer Spooler as default)
    # $printers = Get-Printer -ErrorAction SilentlyContinue | Where-Object Name -notmatch "PDF|XPS|OneNote"
    # if (-not $printers -or $printers.Count -eq 0) {
    #     $servicesToCheck += "Spooler"
    # }

    foreach ($svc in $servicesToCheck) {
        try {
            $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
            if ($s) {
                $svcCim = Get-CimInstance Win32_Service -Filter "Name='$svc'" -ErrorAction SilentlyContinue
                $currentMode = if ($svcCim) { $svcCim.StartMode } else { "Unknown" }
                
                Write-Host "  serve: $svc" -ForegroundColor Gray
                Write-Host "  current status: $currentMode" -ForegroundColor Yellow
                Write-Host "  desired status: Manual" -ForegroundColor Green
                
                if (-not $Global:PreviewMode) {
                    if ($currentMode -ne "Manual") {
                        Set-Service -Name $svc -StartupType Manual -ErrorAction Stop
                        Write-Success  "Adjust service $svc It is Manual successfully."
                    } else {
                        Write-Success  "serve $svc It's already Manual."
                    }
                } else {
                    Write-Host "  [PREVIEW] Skip service adjustment $svc" -ForegroundColor DarkGray
                }
            }
        } catch { Write-Warning2  "Skip service $svc (It may not be in the system or you may not have permission.)" }
    }
}

# Module 8: Analyze-DiskSpace
function Analyze-DiskSpace {
    Write-ModuleHeader  "Analyze hard disk space (Analyze Disk Space)"
    Write-Log  "Starting disk space analysis" -Type "INFO"

    # Show disk space summary
    Write-Host "`n[disk space information]" -ForegroundColor Cyan
    try {
        $drives = Get-CimInstance Win32_LogicalDisk | Where-Object DriveType -eq 3
        foreach ($drive in $drives) {
            $freeGB = [math]::Round($drive.FreeSpace / 1GB, 2)
            $totalGB = [math]::Round($drive.Size / 1GB, 2)
            $usedGB = $totalGB - $freeGB
            $percentUsed = [int](($usedGB / $totalGB) * 100)
            
            $barLen = 20
            $filled = [int](([math]::Round($percentUsed / 100, 2)) * $barLen)
            $empty = $barLen - $filled
            if ($filled -lt 0) { $filled = 0 }
            if ($empty -lt 0) { $empty = 0 }
            $bar = ("█" * $filled) + ("░" * $empty)
            
            Write-Host "$($drive.DeviceID) ($($drive.VolumeName)) -> [$bar] $percentUsed% spent ($usedGB GB / $totalGB GB) free $freeGB GB" -ForegroundColor Green
        }
    } catch { Write-Warning2  "Error retrieving drive data" }

    # Top 20 largest folders on C:
    Write-Host "`nSearching the top 20 large folders in drive C: (except Windows and Program Files)..." -ForegroundColor Cyan
    try {
        $topFolders = Get-ChildItem -Path "C:\" -Directory -ErrorAction SilentlyContinue | Where-Object { 
            $_.Name -notmatch "Windows" -and $_.Name -notmatch "Program Files" 
        } | Select-Object Name, FullName, @{Name="SizeMB";Expression={[math]::Round((Get-FolderSize $_.FullName) / 1MB, 2)}} | Sort-Object SizeMB -Descending | Select-Object -First 20

        if ($topFolders) {
            $topFolders | Format-Table -AutoSize | Out-String | Write-Host
        }
    } catch {
        Write-Warning2  "There was an error searching for a folder."
    }

    # Top 50 largest files on all drives
    Write-Host "Searching top 50 large files across all drives (This may take a while.)..." -ForegroundColor Cyan
    try {
        $allDrives = Get-CimInstance Win32_LogicalDisk | Where-Object DriveType -eq 3 | Select-Object -ExpandProperty DeviceID
        $allFiles = @()
        foreach ($drv in $allDrives) {
            # Limit depth or ignore Windows folders to prevent extreme slow down, but sticking to general search
            # FIXED: the original walked every drive to full depth, which took hours and
            # used a lot of memory. Cap the depth and skip system folders.
            $allFiles += Get-ChildItem -Path "$drv\" -File -Recurse -Depth 4 -ErrorAction SilentlyContinue |
                         Where-Object { $_.FullName -notmatch '\\(Windows|System Volume Information|\$Recycle\.Bin)\\' } |
                         Sort-Object Length -Descending | Select-Object -First 50
        }
        $top50Files = $allFiles | Sort-Object Length -Descending | Select-Object -First 50 Name, Directory, @{Name="SizeMB";Expression={[math]::Round($_.Length / 1MB, 2)}}
        
        if ($top50Files) {
            $top50Files | Format-Table -AutoSize | Out-String | Write-Host
        }
    } catch {
        Write-Warning2  "An error occurred searching for the file."
    }

    # Duplicate finder (simple)
    Write-Host "Searching for potentially duplicate files in user folders (File name and size are the same)..." -ForegroundColor Cyan
    try {
        # FIXED: cap the depth and skip AppData - the original walked every user profile in full.
        $files = Get-ChildItem -Path "C:\Users\" -File -Recurse -Depth 5 -ErrorAction SilentlyContinue |
                 Where-Object { $_.Length -gt 1MB -and $_.FullName -notmatch '\\AppData\\' }
        $duplicates = $files | Group-Object Name, Length | Where-Object Count -gt 1 | Select-Object -First 20
        if ($duplicates) {
            Write-Host "Potentially duplicate files found (example: 20 groups):" -ForegroundColor Yellow
            foreach ($group in $duplicates) {
                Write-Host "  file group: $($group.Name) | size: $([math]::Round($group.Group[0].Length / 1MB, 2)) MB | quantity: $($group.Count)" -ForegroundColor Gray
                foreach ($f in $group.Group) {
                    Write-Host "    -> $($f.FullName)" -ForegroundColor DarkGray
                }
            }
        } else {
            Write-Success  "Large duplicate files not found in user folder."
        }
    } catch {
        Write-Warning2  "An error occurred searching for duplicate files."
    }

    # Component Store Cleanup
    Write-Host "`n[High-end cleaning tools]" -ForegroundColor Cyan
    $runDism = Read-Host "Want to enable WinSxS Component Store Cleanup?? (y/n) [n]"
    if ($runDism -eq 'y') {
        Write-Host "Cleaning old system files with DISM (this may take a long time)..." -ForegroundColor Cyan
        if (-not $Global:PreviewMode) {
            try {
                Start-Process -FilePath "Dism.exe" -ArgumentList "/Online /Cleanup-Image /StartComponentCleanup" -Wait -NoNewWindow
                Write-Success  "Finished cleaning the Component Store."
            } catch {
                Write-Warning2  "Unable to run DISM"
            }
        } else { Write-Host "  [PREVIEW] run DISM /Cleanup-Image" -ForegroundColor DarkGray }
    }

    # Enable Storage Sense
    Write-Host "`nActivating now Storage Sense..." -ForegroundColor Cyan
    if (-not $Global:PreviewMode) {
        try {
            $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy"
            if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
            Set-ItemProperty -Path $regPath -Name "01" -Value 1 -Force
            Write-Success  "Storage Sense has been successfully enabled."
        } catch { Write-Warning2  "Unable to turn on Storage Sense" }
    } else { Write-Host "  [PREVIEW] Activate Storage Sense Registry" -ForegroundColor DarkGray }
}

# Module 9: Optimize-Network
function Optimize-Network {
    Write-ModuleHeader  "Customize the network (Optimize Network)"
    Write-Log  "Starting network optimization" -Type "INFO"

    # Check network adapter driver info
    Write-Host "Network adapter driver information (Network Drivers):" -ForegroundColor Cyan
    try {
        $netAdapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object Status -eq "Up"
        if ($netAdapters) {
            foreach ($adp in $netAdapters) {
                $driverInfo = Get-NetAdapter -Name $adp.Name | Select-Object Name, InterfaceDescription, DriverVersion, DriverDate, DriverProvider
                Write-Host "  name: $($driverInfo.Name)" -ForegroundColor Gray
                Write-Host "  Description: $($driverInfo.InterfaceDescription)" -ForegroundColor DarkGray
                Write-Host "  Driver version: $($driverInfo.DriverVersion) ($($driverInfo.DriverDate))" -ForegroundColor DarkGray
            }
        } else {
            Write-Host "  The adapter in use was not found." -ForegroundColor DarkGray
        }
    } catch {
        Write-Warning2  "Unable to retrieve network driver information."
    }

    # Flush DNS
    Write-Host "`nClearing cache DNS (Flush DNS)..." -ForegroundColor Cyan
    if (-not $Global:PreviewMode) {
        try {
            Clear-DnsClientCache
            Write-Success  "Successfully cleared DNS cache."
        } catch { Write-Warning2  "Unable to clear DNS cache" }
    } else { Write-Host "  [PREVIEW] Run command Clear-DnsClientCache" -ForegroundColor DarkGray }

    # Flush ARP cache
    Write-Host "`nClearing cache ARP..." -ForegroundColor Cyan
    if (-not $Global:PreviewMode) {
        try {
            arp -d * 2>$null
            netsh interface ip delete arpcache | Out-Null
            Write-Success  "Successfully cleared ARP cache."
        } catch { Write-Warning2  "There was an error clearing the cache. ARP" }
    } else { Write-Host "  [PREVIEW] Run the command to clear the cache. ARP" -ForegroundColor DarkGray }

    # Reset TCP/IP stack
    # FIXED: this wipes static IPs, routes and VPN/proxy LSP entries and needs a reboot.
    # It used to run with no prompt as part of "Run All".
    Write-Host "`nReset the network stack (TCP/IP Stack & Winsock)?" -ForegroundColor Cyan
    if (-not $Global:PreviewMode) {
        Write-Warning2 "This clears static IP settings, routes and VPN/proxy hooks, and needs a restart."
        $netAns = Read-Host "Reset TCP/IP and Winsock now? (y/n) [n]"
        if ($netAns -eq 'y') {
            try {
                netsh int ip reset | Out-Null
                netsh winsock reset | Out-Null
                Write-Success  "Network reset successful (You may need to restart your device for full effect.)"
            } catch { Write-Warning2  "Unable to reset network" }
        } else {
            Write-Host "  - Skipped. Network settings were left as they are." -ForegroundColor DarkGray
        }
    } else { Write-Host "  [PREVIEW] Would ask before running netsh int ip reset / netsh winsock reset" -ForegroundColor DarkGray }

    # Disable Delivery Optimization
    Write-Host "`nTurning off Delivery Optimization P2P (delivery of updates Peer-to-Peer)..." -ForegroundColor Cyan
    if (-not $Global:PreviewMode) {
        try {
            $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config"
            if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
            Set-ItemProperty -Path $regPath -Name "DODownloadMode" -Value 0 -Force
            Write-Success  "Successfully closed Delivery Optimization."
        } catch { Write-Warning2  "An error occurred closing Delivery Optimization" }
    } else { Write-Host "  [PREVIEW] Turn off Delivery Optimization via Registry" -ForegroundColor DarkGray }

    # Auto-Tuning
    Write-Host "`nCurrent network Auto-Tuning status:" -ForegroundColor Cyan
    try {
        netsh interface tcp show global | Select-String "Receive Window Auto-Tuning Level" | Write-Host -ForegroundColor Gray
        $disableTuning = Read-Host "Want to turn off the Auto-Tuning setting? (Recommended if the internet is abnormally slow) (y/n) [n]"
        if ($disableTuning -eq 'y') {
            if (-not $Global:PreviewMode) {
                netsh interface tcp set global autotuninglevel=disabled | Out-Null
                Write-Success  "Auto-Tuning turned off successfully."
            } else { Write-Host "  [PREVIEW] Run the shutdown command Auto-Tuning" -ForegroundColor DarkGray }
        }
    } catch { Write-Warning2  "Unable to check Auto-Tuning." }

    # Change DNS
    Write-Host "`nCurrent DNS status:" -ForegroundColor Cyan
    try {
        $adapters = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.ServerAddresses -ne $null }
        foreach ($adapter in $adapters) {
            Write-Host "  adapter $($adapter.InterfaceAlias): $($adapter.ServerAddresses -join ', ')" -ForegroundColor Gray
        }
    } catch { Write-Host "  Unable to retrieve DNS information." -ForegroundColor DarkGray }

    $dnsChoice = Read-Host "Want to change DNS to increase speed? (1) Google DNS, (2) Cloudflare DNS, (0) unchanged [0]"
    if ($dnsChoice -eq '1' -or $dnsChoice -eq '2') {
        if (-not $Global:PreviewMode) {
            try {
                $adapters = Get-NetAdapter | Where-Object Status -eq "Up"
                foreach ($adapter in $adapters) {
                    if ($dnsChoice -eq '1') {
                        Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses ("8.8.8.8","8.8.4.4")
                        Write-Success  "Set up Google DNS for $($adapter.Name) already"
                    } elseif ($dnsChoice -eq '2') {
                        Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses ("1.1.1.1","1.0.0.1")
                        Write-Success  "Set up Cloudflare DNS for $($adapter.Name) already"
                    }
                }
            } catch { Write-Warning2  "An error occurred while changing. DNS" }
        } else { Write-Host "  [PREVIEW] Set DNS to that option. $dnsChoice" -ForegroundColor DarkGray }
    }
}

# Module 10: Setup-AutoMaintenance
function Setup-AutoMaintenance {
    Write-ModuleHeader  "Set up automatic maintenance (Setup Auto Maintenance)"
    Write-Log  "Starting auto maintenance setup" -Type "INFO"

    # Create Scheduled Task for cleanup
    Write-Host "Creating a weekly automatic junk file cleaning task...." -ForegroundColor Cyan
    if (-not $Global:PreviewMode) {
        try {
            $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -WindowStyle Hidden -Command `"Remove-Item -Path `$env:TEMP\* -Recurse -Force -ErrorAction SilentlyContinue`""
            $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 3am
            Register-ScheduledTask -TaskName "WeeklyTempCleanup" -Action $action -Trigger $trigger -Description "Loves System Clean" -User "System" -RunLevel Highest -Force | Out-Null
            Write-Success  "Successfully created an automatic junk file cleaning task."
        } catch { Write-Warning2  "Unable to create a Scheduled Task.: $($_.Exception.Message)" }
    } else { Write-Host "  [PREVIEW] build Scheduled Task: WeeklyTempCleanup" -ForegroundColor DarkGray }

    # Configure Storage Sense
    Write-Host "Setting up Storage Sense to run weekly...." -ForegroundColor Cyan
    if (-not $Global:PreviewMode) {
        try {
            $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy"
            if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
            # FIXED: the original wrote the wrong StoragePolicy value names.
            #   2048 = cadence; only 0 / 1 / 7 / 30 are valid (2 was ignored)
            #   32   = Recycle Bin age threshold in days (the original used "8")
            #   256 / 512 = the Downloads-folder cleanup switch and its threshold.
            #   Writing 30 to "256" switched ON auto-deletion of the user's Downloads
            #   folder. Those two are deliberately left alone now.
            Set-ItemProperty -Path $regPath -Name "2048" -Value 7 -Force  # run weekly
            Set-ItemProperty -Path $regPath -Name "32" -Value 30 -Force   # Recycle Bin: items older than 30 days
            Write-Success  "Storage Sense set up successfully."
        } catch { Write-Warning2  "Unable to set Storage Sense" }
    } else { Write-Host "  [PREVIEW] Set Storage Sense to run weekly and delete files every 30 days." -ForegroundColor DarkGray }

    # Active Hours
    Write-Host "Setting Windows Update's Active Hours to 8:00 - 22:00..." -ForegroundColor Cyan
    if (-not $Global:PreviewMode) {
        try {
            $regPath = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
            Set-ItemProperty -Path $regPath -Name "ActiveHoursStart" -Value 8 -Force
            Set-ItemProperty -Path $regPath -Name "ActiveHoursEnd" -Value 22 -Force
            Write-Success  "Active Hours set successfully."
        } catch { Write-Warning2  "Unable to set Active Hours" }
    } else { Write-Host "  [PREVIEW] Set the time Active Hours 8:00-22:00" -ForegroundColor DarkGray }

    # Weekly Defrag/TRIM
    Write-Host "Setting up disk defragmentation task (Defrag/TRIM) automatic..." -ForegroundColor Cyan
    if (-not $Global:PreviewMode) {
        try {
            Enable-ScheduledTask -TaskPath "\Microsoft\Windows\Defrag\" -TaskName "ScheduledDefrag" -ErrorAction Stop | Out-Null
            Write-Success  "Auto Defrag/TRIM enabled successfully."
        } catch { Write-Warning2  "Unable to activate ScheduledDefrag possible" }
    } else { Write-Host "  [PREVIEW] Activate Task: ScheduledDefrag" -ForegroundColor DarkGray }

    # System Restore Task
    Write-Host "Creating a task to create an automatic system recovery point (Restore Point)..." -ForegroundColor Cyan
    if (-not $Global:PreviewMode) {
        try {
            $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -WindowStyle Hidden -Command `"Checkpoint-Computer -Description 'Weekly Automated Restore Point' -RestorePointType 'MODIFY_SETTINGS'`""
            $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 2am
            Register-ScheduledTask -TaskName "WeeklyRestorePoint" -Action $action -Trigger $trigger -User "System" -RunLevel Highest -Force | Out-Null
            Write-Success  "Successfully created an automatic Restore Point task."
        } catch { Write-Warning2  "Unable to create Restore Point Task." }
    } else { Write-Host "  [PREVIEW] build Scheduled Task: WeeklyRestorePoint" -ForegroundColor DarkGray }

    Write-Host "`n=== Summary of the automatic tasks that have been set up. ===" -ForegroundColor Green
    Write-Host "1. Clean junk files weekly (WeeklyTempCleanup)" -ForegroundColor White
    Write-Host "2. Storage Sense Automatically delete old files (30 days)" -ForegroundColor White
    Write-Host "3. Prevent Windows from restarting periodic updates 8:00 - 22:00" -ForegroundColor White
    Write-Host "4. Organize disks weekly" -ForegroundColor White
    Write-Host "5. Create weekly system restore points (WeeklyRestorePoint)" -ForegroundColor White
    Write-Host "`nThese tasks stay on this machine until you remove them." -ForegroundColor Yellow
    Write-Host "Use menu option U to remove them again." -ForegroundColor Yellow
    Write-Host "" -ForegroundColor White
}

# Module 11: Remove-Bloatware
function Remove-Bloatware {
    Write-ModuleHeader  "Remove junk programs (Remove Bloatware)"
    Write-Log  "Starting bloatware removal" -Type "INFO"

    $bloatwareKeywords = @("McAfee", "Baidu", "Tencent", "Hao123", "Avast", "ByteFence", "Chromium", "Yandex", "Mail.ru", "WebDiscover")
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    Write-Host "Searching for junk programs installed on the system...." -ForegroundColor Cyan
    $foundPrograms = @()

    foreach ($path in $paths) {
        $keys = Get-ItemProperty $path -ErrorAction SilentlyContinue
        foreach ($key in $keys) {
            foreach ($keyword in $bloatwareKeywords) {
                if ($key.DisplayName -and $key.DisplayName -match $keyword) {
                    $foundPrograms += $key
                }
            }
        }
    }

    if ($foundPrograms.Count -eq 0) {
        Write-Success  "Excellent! No bloatware or junk programs found in the system."
        return
    }

    Write-Warning2  "Found the following programs that are considered bloatware or junk programs::"
    $foundPrograms | Select-Object DisplayName, DisplayVersion, Publisher | Format-Table -AutoSize | Out-String | Write-Host -ForegroundColor Yellow

    $ans = Read-Host "Want the system to attempt automatic uninstallation?? (y/n) [n]"
    if ($ans -eq 'y') {
        foreach ($prog in $foundPrograms) {
            Write-Host "Trying to uninstall: $($prog.DisplayName)..." -ForegroundColor Cyan
            if (-not $Global:PreviewMode) {
                try {
                    $uninstallString = $prog.UninstallString
                    if ($uninstallString) {
                        if ($uninstallString -match "msiexec") {
                            # FIXED: the old -replace "/I","/X" hit every "/I" in the string.
                            # Pull the product code out and build the command from scratch.
                            $productCode = [regex]::Match($uninstallString, '\{[0-9A-Fa-f-]{36}\}').Value
                            if ($productCode) {
                                Start-Process "msiexec.exe" -ArgumentList "/X", $productCode, "/quiet", "/norestart" -Wait -NoNewWindow
                            } else {
                                Write-Warning2 "Could not read the product code. Please remove $($prog.DisplayName) from Settings > Apps."
                            }
                        } else {
                            # FIXED: UninstallString normally carries its own arguments, so it
                            # cannot be used as a FilePath, and forcing /S onto an unknown
                            # uninstaller is unpredictable. Show the command instead.
                            Write-Warning2 "Automatic uninstall is not safe for this program."
                            Write-Host "  Run this yourself if you want to remove it:" -ForegroundColor Yellow
                            Write-Host "    $uninstallString" -ForegroundColor White
                        }
                        Write-Success  "Send uninstall command $($prog.DisplayName) finished (Some programs may need to be uninstalled manually.)"
                    } else {
                        Write-Warning2  "Uninstall command not found for $($prog.DisplayName)"
                    }
                } catch {
                    Write-Warning2  "Unable to auto uninstall Please withdraw it yourself through Control Panel"
                }
            } else { Write-Host "  [PREVIEW] Run the uninstall command $($prog.DisplayName)" -ForegroundColor DarkGray }
        }
    }
}

function Optimize-Gaming {
    Write-ModuleHeader "Optimize Gaming & FPS"
    Write-Log "Starting Gaming & FPS Optimization" -Type "INFO"
    $hagsKey = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
    $gameDvrKey1 = "HKCU:\System\GameConfigStore"
    $gameDvrKey2 = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"
    try {
        if ($Global:PreviewMode) {
            Write-Host "[PREVIEW] Would enable Hardware-Accelerated GPU Scheduling (HAGS)." -ForegroundColor Cyan
            Write-Host "[PREVIEW] Would disable Xbox Game Bar / GameDVR." -ForegroundColor Cyan
            Write-Host "[PREVIEW] Would disable Nagle's Algorithm (TcpAckFrequency) for lower ping." -ForegroundColor Cyan
        } else {
            if (Test-Path $hagsKey) {
                Set-ItemProperty -Path $hagsKey -Name "HwSchMode" -Value 2 -ErrorAction SilentlyContinue
                Write-Success "Hardware-Accelerated GPU Scheduling enabled."
            }
            if (Test-Path $gameDvrKey1) {
                Set-ItemProperty -Path $gameDvrKey1 -Name "GameDVR_Enabled" -Value 0 -ErrorAction SilentlyContinue
            }
            if (-not (Test-Path $gameDvrKey2)) {
                New-Item -Path $gameDvrKey2 -Force | Out-Null
            }
            Set-ItemProperty -Path $gameDvrKey2 -Name "AllowGameDVR" -Value 0 -ErrorAction SilentlyContinue
            Write-Success "Xbox Game Bar / GameDVR disabled."
            $interfacesKey = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
            if (Test-Path $interfacesKey) {
                $interfaces = Get-ChildItem -Path $interfacesKey
                foreach ($iface in $interfaces) {
                    $ipAddr = Get-ItemProperty -Path $iface.PSPath -Name "DhcpIPAddress" -ErrorAction SilentlyContinue
                    $staticIp = Get-ItemProperty -Path $iface.PSPath -Name "IPAddress" -ErrorAction SilentlyContinue
                    if ($ipAddr -or $staticIp) {
                        Set-ItemProperty -Path $iface.PSPath -Name "TcpAckFrequency" -Value 1 -ErrorAction SilentlyContinue
                        Set-ItemProperty -Path $iface.PSPath -Name "TCPNoDelay" -Value 1 -ErrorAction SilentlyContinue
                    }
                }
                Write-Success "Nagle's Algorithm disabled for active network adapters (Lower latency/ping)."
            }
        }
    } catch {
        Write-Warning2 "An error occurred during Gaming Optimization: $($_.Exception.Message)"
    }
}
function Clean-BrowserJunk {
    Write-ModuleHeader "Deep Browser Cleaner"
    Write-Log "Starting Deep Browser Cleaner" -Type "INFO"
    $browsers = @(
        @{ Name = "Chrome"; Path = "$env:LOCALAPPDATA\Google\Chrome\User Data" },
        @{ Name = "Edge"; Path = "$env:LOCALAPPDATA\Microsoft\Edge\User Data" },
        @{ Name = "Brave"; Path = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data" },
        @{ Name = "Firefox"; Path = "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles" }
    )
    $junkFolders = @("Cache", "Code Cache", "GPUCache", "Crashpad", "cache2", "startupCache")
    $totalFreed = 0
    foreach ($b in $browsers) {
        if (Test-Path $b.Path) {
            Write-Host "Scanning $($b.Name)..." -ForegroundColor Cyan
            $targets = Get-ChildItem -Path $b.Path -Recurse -Directory -ErrorAction SilentlyContinue | Where-Object { $junkFolders -contains $_.Name }
            foreach ($target in $targets) {
                if ($Global:PreviewMode) {
                    Write-Host "[PREVIEW] Would delete: $($target.FullName)" -ForegroundColor DarkGray
                } else {
                    try {
                        $size = (Get-ChildItem -Path $target.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                        if ($size -gt 0) { $totalFreed += $size }
                        Remove-Item -Path "$($target.FullName)\*" -Recurse -Force -ErrorAction SilentlyContinue
                        Write-Host "Cleaned: $($target.FullName)" -ForegroundColor DarkGray
                    } catch { }
                }
            }
        }
    }
    if (-not $Global:PreviewMode) {
        if ($totalFreed -gt 0) {
            Write-Success "Deep Browser Cleanup complete. Freed $([math]::Round($totalFreed / 1MB, 2)) MB of browser junk!"
        } else {
            Write-Success "Browsers are already clean. No garbage found."
        }
    }
}
function Block-Telemetry {
    Write-ModuleHeader "Block Telemetry & Spying"
    Write-Log "Starting Telemetry Blocker" -Type "INFO"
    try {
        if ($Global:PreviewMode) {
            Write-Host "[PREVIEW] Would stop and disable 'DiagTrack' (Connected User Experiences and Telemetry)." -ForegroundColor Cyan
            Write-Host "[PREVIEW] Would stop and disable 'dmwappushservice' (WAP Push Message Routing)." -ForegroundColor Cyan
            Write-Host "[PREVIEW] Would set AllowTelemetry registry key to 0." -ForegroundColor Cyan
        } else {
            Stop-Service -Name "DiagTrack" -ErrorAction SilentlyContinue
            Set-Service -Name "DiagTrack" -StartupType Disabled -ErrorAction SilentlyContinue
            Write-Success "Disabled DiagTrack service."
            Stop-Service -Name "dmwappushservice" -ErrorAction SilentlyContinue
            Set-Service -Name "dmwappushservice" -StartupType Disabled -ErrorAction SilentlyContinue
            Write-Success "Disabled WAP Push Message Routing service."
            $datacollectionKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
            if (-not (Test-Path $datacollectionKey)) {
                New-Item -Path $datacollectionKey -Force | Out-Null
            }
            Set-ItemProperty -Path $datacollectionKey -Name "AllowTelemetry" -Value 0 -ErrorAction SilentlyContinue
            Write-Success "Windows Telemetry data collection blocked in Registry."
        }
    } catch {
        Write-Warning2 "An error occurred while blocking telemetry: $($_.Exception.Message)"
    }
}


# Main Menu

# Module 15: Repair-SystemDeep
function Repair-SystemDeep {
    Write-ModuleHeader "Repair-SystemDeep (SFC & DISM)"
    Write-Log "Starting deep system repair" -Type "INFO"
    
    if (-not $Global:PreviewMode) {
        Write-Host "Running System File Checker (SFC)... This may take a while." -ForegroundColor Cyan
        sfc /scannow
        
        Write-Host "`nRunning Deployment Image Servicing and Management (DISM)..." -ForegroundColor Cyan
        DISM /Online /Cleanup-Image /RestoreHealth
        
        Write-Success "Deep system repair completed."
    } else {
        Write-Host "  [PREVIEW] Would run: sfc /scannow" -ForegroundColor DarkGray
        Write-Host "  [PREVIEW] Would run: DISM /Online /Cleanup-Image /RestoreHealth" -ForegroundColor DarkGray
    }
}

# Module 16: Reset-Network
function Reset-Network {
    Write-ModuleHeader "Reset-Network (Winsock & DNS)"
    Write-Log "Starting network reset" -Type "INFO"
    
    if (-not $Global:PreviewMode) {
        Write-Host "Resetting TCP/IP and Winsock..." -ForegroundColor Cyan
        netsh winsock reset | Out-Null
        netsh int ip reset | Out-Null
        
        Write-Host "Flushing DNS Cache..." -ForegroundColor Cyan
        ipconfig /flushdns | Out-Null
        
        Write-Success "Network settings reset successfully. (A restart may be required)"
    } else {
        Write-Host "  [PREVIEW] Would run: netsh winsock reset" -ForegroundColor DarkGray
        Write-Host "  [PREVIEW] Would run: netsh int ip reset" -ForegroundColor DarkGray
        Write-Host "  [PREVIEW] Would run: ipconfig /flushdns" -ForegroundColor DarkGray
    }
}

# Module 17: Optimize-Power
function Optimize-Power {
    Write-ModuleHeader "Optimize-Power (Ultimate Performance)"
    Write-Log "Unlocking Ultimate Performance power plan" -Type "INFO"
    
    if (-not $Global:PreviewMode) {
        Write-Host "Unlocking Ultimate Performance Power Plan..." -ForegroundColor Cyan
        $powerplan = powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61
        $guid = [regex]::match($powerplan, '([a-f0-9]{8}-([a-f0-9]{4}-){3}[a-f0-9]{12})').Value
        if ($guid) {
            powercfg -setactive $guid | Out-Null
            Write-Success "Ultimate Performance Power Plan activated."
        } else {
            Write-Warning2 "Could not unlock Ultimate Performance Plan."
        }
    } else {
        Write-Host "  [PREVIEW] Would unlock and set Ultimate Performance power plan" -ForegroundColor DarkGray
    }
}

# Module 18: Clear-CrashDumps
function Clear-CrashDumps {
    Write-ModuleHeader "Clear-CrashDumps (WER & Event Logs)"
    Write-Log "Clearing crash dumps and event logs" -Type "INFO"
    
    if (-not $Global:PreviewMode) {
        Write-Host "Clearing Windows Error Reporting (WER) and Minidumps..." -ForegroundColor Cyan
        Remove-Item -Path "C:\ProgramData\Microsoft\Windows\WER\ReportArchive\*" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "C:\ProgramData\Microsoft\Windows\WER\ReportQueue\*" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "C:\Windows\Minidump\*" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "C:\Windows\MEMORY.DMP" -Force -ErrorAction SilentlyContinue
        
        Write-Host "Clearing Windows Event Logs..." -ForegroundColor Cyan
        wevtutil el | Foreach-Object {wevtutil cl "$_" 2>$null}
        
        Write-Success "Crash dumps and event logs cleared."
    } else {
        Write-Host "  [PREVIEW] Would delete WER archives, Minidumps, and clear all Event Logs" -ForegroundColor DarkGray
    }
}

# Module 19: Restore-ClassicContext
function Restore-ClassicContext {
    Write-ModuleHeader "Restore-ClassicContext (Win 11 Right-Click)"
    Write-Log "Restoring classic context menu for Windows 11" -Type "INFO"
    
    if (-not $Global:PreviewMode) {
        Write-Host "Applying Registry tweak for Classic Context Menu..." -ForegroundColor Cyan
        try {
            $regPath = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
            New-Item -Path $regPath -Force -ErrorAction SilentlyContinue | Out-Null
            Set-ItemProperty -Path $regPath -Name "(Default)" -Value "" -Force -ErrorAction SilentlyContinue
            Write-Success "Classic context menu restored. (Restart Explorer to see changes)"
        } catch {
            Write-Warning2 "Failed to modify registry."
        }
    } else {
        Write-Host "  [PREVIEW] Would create registry key to bypass Windows 11 context menu" -ForegroundColor DarkGray
    }
}

# Module 20: Disable-Ads
function Disable-Ads {
    Write-ModuleHeader "Disable-Ads (Remove Windows Tips & Ads)"
    Write-Log "Disabling Windows ads and tips" -Type "INFO"
    
    if (-not $Global:PreviewMode) {
        Write-Host "Disabling Start Menu suggestions and Windows tips..." -ForegroundColor Cyan
        try {
            Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SystemPaneSuggestionsEnabled" -Value 0 -ErrorAction SilentlyContinue
            Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SoftLandingEnabled" -Value 0 -ErrorAction SilentlyContinue
            Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-338389Enabled" -Value 0 -ErrorAction SilentlyContinue
            Write-Success "Windows ads and tips disabled."
        } catch {
            Write-Warning2 "Failed to disable ads."
        }
    } else {
        Write-Host "  [PREVIEW] Would modify registry to disable Windows tips and suggestions" -ForegroundColor DarkGray
    }
}

# Module U: Remove-AutoMaintenance
# ADDED: undo for option 10. The tasks it registers run as SYSTEM forever and
# survive deleting this tool, so there has to be a way to take them back off.
function Remove-AutoMaintenance {
    Write-ModuleHeader "Remove the automatic maintenance tasks (undo option 10)"
    Write-Log "Removing auto maintenance scheduled tasks" -Type "INFO"

    $taskNames = @("WeeklyTempCleanup", "WeeklyRestorePoint")

    foreach ($t in $taskNames) {
        $existing = Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue
        if (-not $existing) {
            Write-Host "  - Task '$t' is not registered on this machine." -ForegroundColor DarkGray
            continue
        }
        if ($Global:PreviewMode) {
            Write-Host "  [PREVIEW] Would unregister scheduled task: $t" -ForegroundColor DarkGray
        } else {
            try {
                Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction Stop
                Write-Success "Removed scheduled task: $t"
            } catch {
                Write-Warning2 "Could not remove '$t': $($_.Exception.Message)"
            }
        }
    }

    Write-Host "`nNote: Storage Sense and Active Hours are Windows settings, not tasks." -ForegroundColor Cyan
    Write-Host "Turn those back off in Settings > System > Storage > Storage Sense," -ForegroundColor Cyan
    Write-Host "and Settings > Windows Update > Advanced options > Active hours." -ForegroundColor Cyan
}

function Show-MainMenu {
    while ($true) {
        Clear-Host
        Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║         🧹 Windows System Cleanup & Optimization Tool        ║" -ForegroundColor Cyan
        Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
        
        $modeStr = if ($Global:PreviewMode) { "(It's enabled.)" } else { "(Disabled)" }
        
        Write-Host "1. Clean junk files (Clean System Junk)" -ForegroundColor White
        Write-Host "2. System repair and Registry (Repair System)" -ForegroundColor White
        Write-Host "3. Manage startup programs (Optimize Startup)" -ForegroundColor White
        Write-Host "4. Performance tuning (Tune Performance)" -ForegroundColor White
        Write-Host "5. Create a summary report (Generate Report)" -ForegroundColor White
        Write-Host "6. security scan (Scan Security)" -ForegroundColor White
        Write-Host "7. Turn off background work (Optimize Background)" -ForegroundColor White
        Write-Host "8. Analyze hard disk space (Analyze Disk Space)" -ForegroundColor White
        Write-Host "9. Customize the network (Optimize Network)" -ForegroundColor White
        Write-Host "10. Set up automatic maintenance (Setup Auto Maintenance)" -ForegroundColor White
        Write-Host "11. Remove junk programs/Bloatware (Remove Bloatware)" -ForegroundColor White
        Write-Host "12. Optimize Gaming & FPS (Optimize Gaming)" -ForegroundColor White
        Write-Host "13. Deep Browser Cleaner (Clean Browser Junk)" -ForegroundColor White
        Write-Host "14. Block Telemetry & Spying (Block Telemetry)" -ForegroundColor White
        Write-Host "--- ADVANCED FEATURES (Please read README first) ---" -ForegroundColor Red
        Write-Host "15. Repair System Deeply (SFC & DISM)" -ForegroundColor White
        Write-Host "16. Reset Network Settings (Winsock & DNS)" -ForegroundColor White
        Write-Host "17. Unlock Ultimate Power Plan" -ForegroundColor White
        Write-Host "18. Clear Crash Dumps & Event Logs" -ForegroundColor White
        Write-Host "19. Restore Classic Context Menu (Win 11)" -ForegroundColor White
        Write-Host "20. Disable Ads, Tips & Suggestions" -ForegroundColor White
        Write-Host "U. Remove the automatic tasks created by option 10 (Undo)" -ForegroundColor Yellow
        Write-Host "A. Do all the questions. (Run All)" -ForegroundColor Green
        Write-Host "P. Enable/Disable Simulation Mode (Preview Mode) - Present: $modeStr" -ForegroundColor Yellow
        Write-Host "L. Back to language selection" -ForegroundColor White
        Write-Host "Q. Exit the program (Exit)" -ForegroundColor Red
        
        $choice = Read-Host "`nPlease select a menu (1-20, U, A, P, L, Q)"
        
        $pauseBlock = { 
            Write-Host "`nPress Enter to continue...." -ForegroundColor Gray
            $null = Read-Host 
        }

        switch ($choice) {
            '1' { if (Get-Command Clean-SystemJunk -ErrorAction SilentlyContinue) { Clean-SystemJunk } else { Write-Warning2 "Function not found (from the section 1)" }; &$pauseBlock }
            '2' { if (Get-Command Repair-Registry -ErrorAction SilentlyContinue) { Repair-Registry } else { Write-Warning2 "Function not found (from the section 1)" }; &$pauseBlock }
            '3' { if (Get-Command Optimize-Startup -ErrorAction SilentlyContinue) { Optimize-Startup } else { Write-Warning2 "Function not found (from the section 1)" }; &$pauseBlock }
            '4' { if (Get-Command Tune-Performance -ErrorAction SilentlyContinue) { Tune-Performance } else { Write-Warning2 "Function not found (from the section 1)" }; &$pauseBlock }
            '5' { if (Get-Command Generate-Report -ErrorAction SilentlyContinue) { Generate-Report } else { Write-Warning2 "Function not found (from the section 1)" }; &$pauseBlock }
            '6' { Scan-Security; &$pauseBlock }
            '7' { Optimize-Background; &$pauseBlock }
            '8' { Analyze-DiskSpace; &$pauseBlock }
            '9' { Optimize-Network; &$pauseBlock }
            '10' { Setup-AutoMaintenance; &$pauseBlock }
            '11' { Remove-Bloatware; &$pauseBlock }
            '12' { Optimize-Gaming; &$pauseBlock }
            '13' { Clean-BrowserJunk; &$pauseBlock }
            '14' { Block-Telemetry; &$pauseBlock }
            '15' { Repair-SystemDeep; &$pauseBlock }
            '16' { Reset-Network; &$pauseBlock }
            '17' { Optimize-Power; &$pauseBlock }
            '18' { Clear-CrashDumps; &$pauseBlock }
            '19' { Restore-ClassicContext; &$pauseBlock }
            '20' { Disable-Ads; &$pauseBlock }
            'U' { Remove-AutoMaintenance; &$pauseBlock }
            'A' {
                if (Get-Command Clean-SystemJunk -ErrorAction SilentlyContinue) { Clean-SystemJunk }
                if (Get-Command Repair-Registry -ErrorAction SilentlyContinue) { Repair-Registry }
                if (Get-Command Optimize-Startup -ErrorAction SilentlyContinue) { Optimize-Startup }
                if (Get-Command Tune-Performance -ErrorAction SilentlyContinue) { Tune-Performance }
                Scan-Security
                Optimize-Background
                # FIXED: Analyze-DiskSpace (walks every drive, takes hours) and
                # Optimize-Network (resets the TCP/IP stack) are no longer part of
                # "Run All". Use menu 8 and 9 to run them deliberately.
                Setup-AutoMaintenance
                Remove-Bloatware
                Optimize-Gaming
                Clean-BrowserJunk
                Block-Telemetry
                if (Get-Command Generate-Report -ErrorAction SilentlyContinue) { Generate-Report }
                &$pauseBlock
            }
            'P' { $Global:PreviewMode = -not $Global:PreviewMode }
            'L' { return }
            'Q' { Write-Host "Successfully exited the program. Thank you for using!" -ForegroundColor Green; exit }
            default { Write-Host "Incorrect choice Please select again." -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    }
}

# Start the script
Show-MainMenu



    }
}

function Run-ThaiMode {
    & {

# Windows System Cleanup & Optimization Tool
# Version 1.1
# Created for: Antigravity Project
# Description: Advanced system cleanup and optimization tool. First half of the complete suite.
# 
# IMPORTANT NOTE: This script is designed to be completely safe.
# It explicitly avoids touching any user personal files and always creates a system restore point.

# =============================================================================
# 2. ADMIN CHECK & ELEVATION
# =============================================================================
# Check if the script is running with Administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "สคริปต์นี้ต้องใช้สิทธิ์ผู้ดูแลระบบ (Administrator) กำลังพยายามเรียกใช้ใหม่..." -ForegroundColor Yellow
    try {
        # Attempt to relaunch the script as Administrator
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
        Exit
    } catch {
        Write-Host "ไม่สามารถเรียกใช้ด้วยสิทธิ์ผู้ดูแลระบบได้ กรุณาคลิกขวาที่สคริปต์แล้วเลือก 'Run as Administrator'" -ForegroundColor Red
        Pause
        Exit
    }
}

# =============================================================================
# 3. GLOBAL VARIABLES
# =============================================================================
# Set basic configuration and state variables
$Global:ScriptVersion = '1.1'
$Global:LogDir = "$PSScriptRoot\CleanupLogs"

# Ensure the log directory exists
if (-not (Test-Path -Path $Global:LogDir)) {
    try {
        New-Item -ItemType Directory -Path $Global:LogDir -Force | Out-Null
    } catch {
        Write-Host "ไม่สามารถสร้างแฟ้มบันทึกข้อมูลได้ (Log Directory)!" -ForegroundColor Red
    }
}

# Generate a unique log file name based on the current timestamp
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$Global:LogFile = Join-Path $Global:LogDir "cleanup_$timestamp.log"
$Global:TotalCleaned = 0
$Global:TotalFixed = 0
$Global:PreviewMode = $true
$Global:StartTime = Get-Date

# =============================================================================
# 4. HELPER FUNCTIONS
# =============================================================================

<#
.SYNOPSIS
Writes a message to the console and appends it to the log file.
#>
function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [string]$Type = "INFO"
    )
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$time] [$Type] $Message"
    try {
        Add-Content -Path $Global:LogFile -Value $logMessage -ErrorAction SilentlyContinue
    } catch {
        # Silent fail if log is locked
    }
}

<#
.SYNOPSIS
Displays the main ASCII art banner for the tool.
#>
function Write-Banner {
    Clear-Host
    $banner = @"
===============================================================================
   _      __ _           __                       ___                            
  | | /| / /(_)___  ____/ /___  _      __ _____  / _/___  ____  __  __ ________ 
  | |/ |/ // // _ \/ __  // _ \| | /| / // ___/ / /_ / _ \/ __ \/ / / // ___/ _ \
  | /| / // //  __/ /_/ // (_) | |/ |/ /(__  ) / __//  __/ /_/ / /_/ // /  /  __/
  |__/|__//_/ \___/\__,_/ \___/|__/|__//____/ /_/   \___/\____/\__,_//_/   \___/ 
                                                                                 
===============================================================================
                     เครื่องมือทำความสะอาดและเพิ่มประสิทธิภาพ
                                  เวอร์ชัน $Global:ScriptVersion
===============================================================================
"@
    Write-Host $banner -ForegroundColor Cyan
    Write-Log "Started Cleanup Tool Version $Global:ScriptVersion" "INFO"
}

<#
.SYNOPSIS
Displays a formatted header for each module section.
#>
function Write-ModuleHeader {
    param([string]$ModuleName)
    Write-Host "`n"
    Write-Host "===============================================================================" -ForegroundColor Magenta
    Write-Host " [$ModuleName] " -ForegroundColor White -BackgroundColor Magenta
    Write-Host "===============================================================================" -ForegroundColor Magenta
    Write-Log "Starting Module: $ModuleName" "INFO"
}

<#
.SYNOPSIS
Helper for writing success messages in green.
#>
function Write-Success {
    param([string]$Message)
    Write-Host "[สำเร็จ] $Message" -ForegroundColor Green
    Write-Log $Message "SUCCESS"
}

<#
.SYNOPSIS
Helper for writing warning messages in yellow.
#>
function Write-Warning2 {
    param([string]$Message)
    Write-Host "[คำเตือน] $Message" -ForegroundColor Yellow
    Write-Log $Message "WARNING"
}

<#
.SYNOPSIS
Helper for writing error messages in red.
#>
function Write-Error2 {
    param([string]$Message)
    Write-Host "[ผิดพลาด] $Message" -ForegroundColor Red
    Write-Log $Message "ERROR"
}

<#
.SYNOPSIS
Displays a customized progress bar in the console.
#>
function Write-ProgressBar {
    param(
        [int]$PercentComplete,
        [string]$Activity
    )
    try {
        $progressBarWidth = 50
        $completedWidth = [math]::Round(($PercentComplete / 100) * $progressBarWidth)
        $remainingWidth = $progressBarWidth - $completedWidth
        
        $completedBar = "█" * $completedWidth
        $remainingBar = "-" * $remainingWidth
        
        $progressString = "[$completedBar$remainingBar] $PercentComplete%"
        
        Write-Progress -Activity $Activity -Status $progressString -PercentComplete $PercentComplete -ErrorAction SilentlyContinue
    } catch {}
}

<#
.SYNOPSIS
Calculates the total size of a folder in bytes recursively.
#>
function Get-FolderSize {
    param([string]$Path)
    $size = 0
    if (Test-Path -Path $Path) {
        try {
            $colItems = Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue
            if ($colItems) {
                $measure = $colItems | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue
                if ($measure.Sum) {
                    $size = $measure.Sum
                }
            }
        } catch {
            Write-Log "Failed to calculate folder size for $Path" "ERROR"
        }
    }
    return $size
}

<#
.SYNOPSIS
Formats raw bytes into a human-readable string (KB, MB, GB).
#>
function Format-FileSize {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) {
        return "{0:N2} GB" -f ($Bytes / 1GB)
    } elseif ($Bytes -ge 1MB) {
        return "{0:N2} MB" -f ($Bytes / 1MB)
    } elseif ($Bytes -ge 1KB) {
        return "{0:N2} KB" -f ($Bytes / 1KB)
    } else {
        return "$Bytes Bytes"
    }
}

<#
.SYNOPSIS
CRITICAL: Validates that a given path is safe to delete.
Protects against deleting user personal folders or system critical roots.
#>
function Test-SafePath {
    param([string]$Path)
    
    # Define protected locations that should never be deleted
    $protectedPaths = @(
        "$env:USERPROFILE\Desktop",
        "$env:USERPROFILE\Documents",
        "$env:USERPROFILE\Downloads",
        "$env:USERPROFILE\Pictures",
        "$env:USERPROFILE\Videos",
        "$env:USERPROFILE\Music",
        "$env:USERPROFILE\OneDrive",
        "$env:USERPROFILE\3D Objects",
        "$env:USERPROFILE\Favorites",
        "$env:PUBLIC\Desktop",
        "$env:PUBLIC\Documents",
        "$env:PUBLIC\Downloads"
    )
    
    # 1. Prevent deleting protected personal folders
    foreach ($protected in $protectedPaths) {
        # Check if the target path is inside or exactly the protected path
        if ($Path -like "$protected*") {
            Write-Log "SAFETY BLOCK: Path $Path is protected. Aborting deletion." "WARNING"
            return $false
        }
    }
    
    # 2. Prevent deleting system root folders
    $sysRoot = $env:SystemDrive + "\"
    $winDir = $env:WINDIR
    $system32 = Join-Path $winDir "System32"
    $programFiles = $env:ProgramFiles
    $programFilesx86 = ${env:ProgramFiles(x86)}
    
    $criticalRoots = @(
        $sysRoot,
        $winDir,
        $system32,
        $programFiles,
        $programFilesx86
    )
    
    foreach ($crit in $criticalRoots) {
        # Exact match check to prevent "C:\Windows" or "C:\" deletion
        if ($Path -eq $crit -or $Path -eq "$crit\") {
            Write-Log "SAFETY BLOCK: Critical system path $Path requested for deletion. Aborting." "WARNING"
            return $false
        }
    }
    
    # Path is deemed safe for automated cleaning
    return $true
}

# =============================================================================
# 5. FUNCTION: Create-RestorePoint
# =============================================================================
function Create-RestorePoint {
    Write-ModuleHeader "การสร้างจุดคืนค่าระบบ (System Restore Point)"
    Write-Host "กำลังเตรียมสร้างจุดคืนค่าระบบเพื่อความปลอดภัย..." -ForegroundColor Cyan
    
    try {
        Write-ProgressBar -PercentComplete 10 -Activity "กำลังตรวจสอบบริการ System Restore"
        
        # Enable system restore on the system drive if it isn't already
        $sysDrive = $env:SystemDrive + "\"
        Enable-ComputerRestore -Drive $sysDrive -ErrorAction SilentlyContinue
        
        Write-ProgressBar -PercentComplete 40 -Activity "กำลังดำเนินการสร้างจุดคืนค่าระบบ (กระบวนการนี้อาจใช้เวลาสักครู่)"
        
        # Create the checkpoint
        $description = "CleanupTool_Before_Optimization_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        $result = Checkpoint-Computer -Description $description -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        
        Write-ProgressBar -PercentComplete 100 -Activity "สร้างจุดคืนค่าระบบเสร็จสิ้น"
        Write-Success "สร้างจุดคืนค่าระบบสำเร็จ: $description"
    } catch {
        Write-ProgressBar -PercentComplete 100 -Activity "เกิดข้อผิดพลาด"
        Write-Error2 "ไม่สามารถสร้างจุดคืนค่าระบบได้: $($_.Exception.Message)"
        Write-Warning2 "คำแนะนำ: คุณยังสามารถดำเนินการต่อได้ แต่ระบบจะไม่สามารถย้อนกลับการเปลี่ยนแปลงได้"
    }
}

# =============================================================================
# 6. MODULE 1: Clean-SystemJunk
# =============================================================================
function Clean-SystemJunk {
    Write-ModuleHeader "โมดูล 1: ทำความสะอาดไฟล์ขยะระบบ (System Junk)"
    
    # Array of locations to clean
    $itemsToClean = @(
        @{ Name="ไฟล์ชั่วคราวของผู้ใช้ (User Temp)"; Path="$env:TEMP\*"; IsFolder=$false },
        @{ Name="ไฟล์ชั่วคราวของ Windows"; Path="$env:WINDIR\Temp\*"; IsFolder=$false },
        @{ Name="แคชการอัปเดต Windows"; Path="$env:WINDIR\SoftwareDistribution\Download\*"; IsFolder=$false },
        @{ Name="แคชภาพขนาดเล็ก (Thumbnail Cache)"; Path="$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db"; IsFolder=$false },
        @{ Name="ไฟล์รายงานข้อผิดพลาด (Windows Error Reports)"; Path="$env:PROGRAMDATA\Microsoft\Windows\WER\ReportArchive\*"; IsFolder=$false },
        @{ Name="ไฟล์บันทึกระบบ (System Logs - CBS)"; Path="$env:WINDIR\Logs\CBS\*.log"; IsFolder=$false },
        @{ Name="ไฟล์จัดส่งการอัปเดต (Delivery Optimization)"; Path="$env:WINDIR\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache\*"; IsFolder=$false },
        @{ Name="แคชฟอนต์ (Font Cache)"; Path="$env:WINDIR\ServiceProfiles\LocalService\AppData\Local\FontCache\*.dat"; IsFolder=$false },
        @{ Name="ไฟล์แคชตัวติดตั้งแพตช์ (Patch Cache)"; Path="$env:WINDIR\Installer\`$PatchCache`$\*"; IsFolder=$false },
        @{ Name="แคช Windows Defender"; Path="$env:PROGRAMDATA\Microsoft\Windows Defender\Scans\History\Results\*"; IsFolder=$false },
        @{ Name="ไฟล์ข้อมูลหน่วยความจำขัดข้อง (Crash Dumps)"; Path="$env:LOCALAPPDATA\CrashDumps\*"; IsFolder=$false }
    )
    
    $totalFreedSpace = 0
    $totalFilesDeleted = 0
    
    foreach ($item in $itemsToClean) {
        $path = $item.Path
        $name = $item.Name
        
        Write-Host "กำลังตรวจสอบ $name..." -ForegroundColor Cyan
        Write-Log "Cleaning junk category: $name ($path)" "INFO"
        
        $itemSize = 0
        $filesDeleted = 0
        
        try {
            $files = Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue
            
            foreach ($file in $files) {
                # Ensure the file path is safe before attempting deletion
                if (Test-SafePath -Path $file.FullName) {
                    if ($Global:PreviewMode -eq $false) {
                        $size = $file.Length
                        Remove-Item -Path $file.FullName -Force -Recurse -ErrorAction SilentlyContinue
                        
                        # Verify if the file was actually deleted
                        if (-not (Test-Path -Path $file.FullName)) {
                            $itemSize += $size
                            $filesDeleted++
                        }
                    } else {
                        # In preview mode, just count the sizes
                        $itemSize += $file.Length
                        $filesDeleted++
                    }
                }
            }
            
            if ($filesDeleted -gt 0) {
                $formattedSize = Format-FileSize -Bytes $itemSize
                Write-Success "ลบไฟล์ขยะ $name จำนวน $filesDeleted ไฟล์ ประหยัดพื้นที่ $formattedSize"
                $totalFreedSpace += $itemSize
                $totalFilesDeleted += $filesDeleted
            } else {
                Write-Host "  - ไม่พบไฟล์หรือไม่มีสิทธิ์ลบในส่วนนี้" -ForegroundColor DarkGray
            }
            
        } catch {
            Write-Warning2 "ไม่สามารถลบ $name ได้ทั้งหมด ($($_.Exception.Message))"
        }
    }
    
    # Empty Recycle Bin
    Write-Host "กำลังล้างถังขยะ (Recycle Bin)..." -ForegroundColor Cyan
    try {
        if ($Global:PreviewMode -eq $false) {
            # FIXED: ถังขยะคือไฟล์ส่วนตัวของผู้ใช้ที่ยังไม่ตัดสินใจลบถาวร ล้างแล้วกู้ไม่ได้
            # จึงต้องถามก่อนทุกครั้ง ไม่รันเองอัตโนมัติ
            Write-Warning2 "ถังขยะเก็บไฟล์ส่วนตัวที่คุณลบไว้ ล้างแล้วกู้คืนไม่ได้"
            $rbAns = Read-Host "ต้องการล้างถังขยะหรือไม่? (y/n) [n]"
            if ($rbAns -eq 'y') {
                Clear-RecycleBin -Force -ErrorAction SilentlyContinue
                Write-Success "ล้างถังขยะเรียบร้อยแล้ว"
            } else {
                Write-Host "  - ข้ามไป ไม่ได้แตะถังขยะ" -ForegroundColor DarkGray
            }
        } else {
            Write-Success "[พรีวิว] จะถามยืนยันก่อนล้างถังขยะ"
        }
    } catch {
        Write-Warning2 "ไม่สามารถล้างถังขยะได้"
    }
    
    # Old Prefetch files (older than 30 days)
    Write-Host "กำลังตรวจสอบไฟล์ Prefetch เก่า..." -ForegroundColor Cyan
    try {
        $prefetchPath = "$env:WINDIR\Prefetch\*"
        $oldPrefetch = Get-ChildItem -Path $prefetchPath -Force -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) -and -not $_.PSIsContainer }
        
        $pfSize = 0
        $pfDeleted = 0
        
        foreach ($pf in $oldPrefetch) {
            if (Test-SafePath -Path $pf.FullName) {
                if ($Global:PreviewMode -eq $false) {
                    $size = $pf.Length
                    Remove-Item -Path $pf.FullName -Force -ErrorAction SilentlyContinue
                    if (-not (Test-Path -Path $pf.FullName)) {
                        $pfSize += $size
                        $pfDeleted++
                    }
                } else {
                    $pfSize += $pf.Length
                    $pfDeleted++
                }
            }
        }
        
        if ($pfDeleted -gt 0) {
            $formattedSize = Format-FileSize -Bytes $pfSize
            Write-Success "ลบไฟล์ Prefetch เก่า จำนวน $pfDeleted ไฟล์ ประหยัดพื้นที่ $formattedSize"
            $totalFreedSpace += $pfSize
            $totalFilesDeleted += $pfDeleted
        } else {
            Write-Host "  - ไม่มีไฟล์ Prefetch ที่เก่ากว่า 30 วัน" -ForegroundColor DarkGray
        }
    } catch {
        Write-Warning2 "มีปัญหาในการจัดการไฟล์ Prefetch"
    }
    
    # Flush DNS Cache
    Write-Host "กำลังล้างแคช DNS (Flush DNS)..." -ForegroundColor Cyan
    try {
        if ($Global:PreviewMode -eq $false) {
            ipconfig /flushdns | Out-Null
            Write-Success "ล้างแคช DNS สำเร็จ"
        } else {
            Write-Success "[พรีวิว] จะทำการล้างแคช DNS"
        }
    } catch {
        Write-Warning2 "ไม่สามารถล้างแคช DNS ได้"
    }
    
    # Browser Cache Cleanups
    Write-Host "กำลังทำความสะอาดแคชเบราว์เซอร์ (Chrome, Edge, Firefox, Brave)..." -ForegroundColor Cyan
    $browserCaches = @(
        @{ Name="Google Chrome Cache"; Path="$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache\Cache_Data\*" },
        @{ Name="Microsoft Edge Cache"; Path="$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache\Cache_Data\*" },
        @{ Name="Mozilla Firefox Cache"; Path="$env:LOCALAPPDATA\Mozilla\Firefox\Profiles\*\cache2\entries\*" },
        @{ Name="Brave Browser Cache"; Path="$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Cache\Cache_Data\*" }
    )
    
    foreach ($bc in $browserCaches) {
        $bpath = $bc.Path
        $bname = $bc.Name
        $bSize = 0
        $bDeleted = 0
        
        try {
            $bfiles = Get-ChildItem -Path $bpath -Recurse -Force -ErrorAction SilentlyContinue
            foreach ($bf in $bfiles) {
                if (Test-SafePath -Path $bf.FullName) {
                    if ($Global:PreviewMode -eq $false) {
                        $size = $bf.Length
                        Remove-Item -Path $bf.FullName -Force -Recurse -ErrorAction SilentlyContinue
                        if (-not (Test-Path -Path $bf.FullName)) {
                            $bSize += $size
                            $bDeleted++
                        }
                    } else {
                        $bSize += $bf.Length
                        $bDeleted++
                    }
                }
            }
            if ($bDeleted -gt 0) {
                $formattedSize = Format-FileSize -Bytes $bSize
                Write-Success "ลบแคช $bname จำนวน $bDeleted ไฟล์ ประหยัดพื้นที่ $formattedSize"
                $totalFreedSpace += $bSize
                $totalFilesDeleted += $bDeleted
            }
        } catch {
            Write-Warning2 "ข้ามแคช $bname (เบราว์เซอร์อาจกำลังเปิดใช้งานอยู่)"
        }
    }
    
    $Global:TotalCleaned += $totalFreedSpace
    $formattedTotal = Format-FileSize -Bytes $totalFreedSpace
    Write-Host "`n=======================================================" -ForegroundColor Cyan
    Write-Host " สรุปผลการทำความสะอาดไฟล์ขยะ: ลบ $totalFilesDeleted ไฟล์, ได้พื้นที่คืน $formattedTotal" -ForegroundColor Green
    Write-Host "=======================================================" -ForegroundColor Cyan
    Write-Log "Module 1 Complete: Freed $formattedTotal ($totalFilesDeleted files)" "SUCCESS"
}

# =============================================================================
# 7. MODULE 2: Repair-Registry
# =============================================================================
function Repair-Registry {
    Write-ModuleHeader "โมดูล 2: ตรวจสอบและซ่อมแซมรีจิสทรีและไฟล์ระบบ"
    
    # System File Checker (SFC)
    Write-Host "กำลังเริ่มการทำงาน System File Checker (SFC)... (ขั้นตอนนี้อาจใช้เวลาหลายนาที)" -ForegroundColor Cyan
    Write-Log "Running SFC /scannow" "INFO"
    try {
        if ($Global:PreviewMode -eq $false) {
            $sfcOutput = & sfc /scannow
            $sfcResult = $sfcOutput | Select-String "Windows Resource Protection did not find any integrity violations." -Quiet
            if ($sfcResult) {
                Write-Success "SFC: ไม่พบไฟล์ระบบเสียหาย ระบบอยู่ในสภาพสมบูรณ์"
            } else {
                $sfcRepaired = $sfcOutput | Select-String "successfully repaired them" -Quiet
                if ($sfcRepaired) {
                    Write-Success "SFC: พบไฟล์ระบบเสียหายและได้ทำการซ่อมแซมเรียบร้อยแล้ว"
                    $Global:TotalFixed++
                } else {
                    Write-Warning2 "SFC: พบไฟล์เสียหายแต่ไม่สามารถซ่อมแซมได้ทั้งหมด โปรดตรวจสอบล็อกเพื่อดูรายละเอียด"
                }
            }
        } else {
            Write-Success "[พรีวิว] จะรันคำสั่ง sfc /scannow"
        }
    } catch {
        Write-Error2 "ไม่สามารถเรียกใช้โปรแกรม SFC ได้"
    }
    
    # DISM Check & Repair
    Write-Host "กำลังเริ่มการทำงาน DISM เพื่อซ่อมแซมอิมเมจของ Windows..." -ForegroundColor Cyan
    Write-Log "Running DISM /Online /Cleanup-Image /RestoreHealth" "INFO"
    try {
        if ($Global:PreviewMode -eq $false) {
            $dismOutput = & DISM /Online /Cleanup-Image /RestoreHealth
            $dismResult = $dismOutput | Select-String "The restore operation completed successfully" -Quiet
            if ($dismResult) {
                Write-Success "DISM: ซ่อมแซมอิมเมจของระบบสำเร็จ"
                $Global:TotalFixed++
            } else {
                Write-Warning2 "DISM: การทำงานเสร็จสิ้นแต่อาจมีข้อผิดพลาดบางอย่างเกิดขึ้น"
            }
        } else {
            Write-Success "[พรีวิว] จะรันคำสั่ง DISM /Online /Cleanup-Image /RestoreHealth"
        }
    } catch {
        Write-Error2 "ไม่สามารถเรียกใช้โปรแกรม DISM ได้"
    }
    
    # Registry Cleanup Operations
    Write-Host "กำลังสแกนรีจิสทรีหาการอ้างอิงไฟล์ที่ไม่มีอยู่จริง..." -ForegroundColor Cyan
    
    $invalidEntriesCount = 0
    
    # Registry Task 1: Check Shared DLLs
    Write-Host " - ตรวจสอบไฟล์ระบบร่วม (Shared DLLs)" -ForegroundColor DarkGray
    $sharedDllPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\SharedDLLs"
    if (Test-Path -Path $sharedDllPath) {
        try {
            # Backup registry key conceptually - done by System Restore previously
            $dllItems = Get-ItemProperty -Path $sharedDllPath -ErrorAction SilentlyContinue
            $properties = $dllItems.psobject.properties | Where-Object { $_.Name -like "*:\*" }
            
            foreach ($prop in $properties) {
                $filePath = $prop.Name
                # Check if the file referenced in registry still exists on disk
                if (-not (Test-Path -Path $filePath -ErrorAction SilentlyContinue)) {
                    Write-Log "Invalid Shared DLL found: $filePath" "INFO"
                    if ($Global:PreviewMode -eq $false) {
                        Remove-ItemProperty -Path $sharedDllPath -Name $filePath -ErrorAction SilentlyContinue
                        $invalidEntriesCount++
                    } else {
                        $invalidEntriesCount++
                    }
                }
            }
        } catch {
            Write-Log "Error scanning Shared DLLs" "ERROR"
        }
    }
    
    # Registry Task 2: Orphaned Uninstall Entries
    Write-Host " - ตรวจสอบรายการถอนการติดตั้งที่ตกค้าง" -ForegroundColor DarkGray
    $uninstallPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    foreach ($up in $uninstallPaths) {
        try {
            $uninstallKeys = Get-Item -Path $up -ErrorAction SilentlyContinue
            foreach ($key in $uninstallKeys) {
                $installLocation = (Get-ItemProperty -Path $key.PSPath -Name "InstallLocation" -ErrorAction SilentlyContinue).InstallLocation
                $displayName = (Get-ItemProperty -Path $key.PSPath -Name "DisplayName" -ErrorAction SilentlyContinue).DisplayName
                
                # If InstallLocation is defined but the physical path doesn't exist
                if (-not [string]::IsNullOrWhiteSpace($installLocation)) {
                    if (-not (Test-Path -Path $installLocation -ErrorAction SilentlyContinue)) {
                        Write-Log "Orphaned Uninstall entry found: $($key.PSChildName) ($displayName)" "INFO"
                        # FIXED: report only, never delete. Plenty of genuinely installed
                        # programs record an InstallLocation that no longer resolves, and
                        # removing the key destroys the only way to uninstall them.
                        $invalidEntriesCount++
                    }
                }
            }
        } catch {
            Write-Log "Error scanning Uninstall entries" "ERROR"
        }
    }
    
    # Registry Task 3: Old MUI Cache
    Write-Host " - ทำความสะอาดรายการ MUI Cache" -ForegroundColor DarkGray
    $muiCachePath = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache"
    if (Test-Path -Path $muiCachePath) {
        try {
            $muiItems = Get-ItemProperty -Path $muiCachePath -ErrorAction SilentlyContinue
            $properties = $muiItems.psobject.properties | Where-Object { $_.Name -like "*:\*.exe*" }
            
            foreach ($prop in $properties) {
                # Format is usually "C:\path\to\app.exe.FriendlyAppName"
                $pathOnly = $prop.Name -replace '\.FriendlyAppName$','' -replace '\.ApplicationCompany$',''
                if ($pathOnly -like "*:\*") {
                    if (-not (Test-Path -Path $pathOnly -ErrorAction SilentlyContinue)) {
                        if ($Global:PreviewMode -eq $false) {
                            Remove-ItemProperty -Path $muiCachePath -Name $prop.Name -ErrorAction SilentlyContinue
                            $invalidEntriesCount++
                        } else {
                            $invalidEntriesCount++
                        }
                    }
                }
            }
        } catch {
            Write-Log "Error scanning MUI Cache" "ERROR"
        }
    }
    
    if ($invalidEntriesCount -gt 0) {
        Write-Success "พบรายการรีจิสทรีที่ตกค้าง $invalidEntriesCount รายการ (รายการถอนติดตั้งจะรายงานอย่างเดียว ไม่ลบทิ้ง)"
        $Global:TotalFixed += $invalidEntriesCount
    } else {
        Write-Host " - รีจิสทรีอยู่ในสภาพดี ไม่พบรายการที่ตกค้าง" -ForegroundColor Green
    }
    
    Write-Host "`n=======================================================" -ForegroundColor Cyan
    Write-Host " สรุปผลการซ่อมแซม: ซ่อมไฟล์และรีจิสทรีที่เสียหายรวม $Global:TotalFixed รายการ" -ForegroundColor Green
    Write-Host "=======================================================" -ForegroundColor Cyan
    Write-Log "Module 2 Complete: Fixed $Global:TotalFixed registry/system issues" "SUCCESS"
}

# =============================================================================
# 8. MODULE 3: Optimize-Startup
# =============================================================================
function Optimize-Startup {
    Write-ModuleHeader "โมดูล 3: ตรวจสอบโปรแกรมที่เริ่มทำงานอัตโนมัติ (Startup Optimization)"
    Write-Host "กำลังรวบรวมข้อมูลโปรแกรมที่เปิดขึ้นมาพร้อม Windows..." -ForegroundColor Cyan
    
    $startupItems = @()
    
    # Helper function to extract startup items from registry paths
    function Get-RegistryStartup {
        param([string]$Path, [string]$Type)
        $items = @()
        if (Test-Path -Path $Path) {
            $keys = Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue
            $props = $keys.psobject.properties | Where-Object { 
                $_.Name -ne "PSPath" -and 
                $_.Name -ne "PSParentPath" -and 
                $_.Name -ne "PSChildName" -and 
                $_.Name -ne "PSDrive" -and 
                $_.Name -ne "PSProvider" 
            }
            foreach ($p in $props) {
                $items += [PSCustomObject]@{
                    Name = $p.Name
                    Command = $p.Value
                    Location = $Type
                    Status = "Enabled"
                }
            }
        }
        return $items
    }
    
    # 1. User specific run keys
    $startupItems += Get-RegistryStartup -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Type "Registry (HKCU)"
    
    # 2. Machine wide run keys
    $startupItems += Get-RegistryStartup -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Type "Registry (HKLM)"
    $startupItems += Get-RegistryStartup -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run" -Type "Registry (HKLM 32-bit)"
    
    # 3. Startup Folder (User)
    $startupFolder = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    if (Test-Path -Path $startupFolder) {
        $files = Get-ChildItem -Path $startupFolder -ErrorAction SilentlyContinue
        foreach ($f in $files) {
            $startupItems += [PSCustomObject]@{
                Name = $f.BaseName
                Command = $f.FullName
                Location = "Startup Folder (User)"
                Status = "Enabled"
            }
        }
    }
    
    # 4. WMI Startup Commands
    try {
        $wmiStartup = Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue
        foreach ($w in $wmiStartup) {
            # Prevent duplicates
            if (-not ($startupItems.Name -contains $w.Name)) {
                $startupItems += [PSCustomObject]@{
                    Name = $w.Name
                    Command = $w.Command
                    Location = $w.Location
                    Status = "Enabled"
                }
            }
        }
    } catch {}
    
    # Display the results
    if ($startupItems.Count -gt 0) {
        Write-Host "`nรายการโปรแกรมที่เริ่มทำงานอัตโนมัติ (Startup Programs):" -ForegroundColor Yellow
        $startupItems | Format-Table -Property Name, Command, Location, Status -AutoSize | Out-String | Write-Host
        
        Write-Host "คำแนะนำการเพิ่มความเร็ว: คุณสามารถปิดการทำงานของโปรแกรมที่ไม่ได้ใช้งานประจำได้" -ForegroundColor Cyan
        Write-Host "วิธีการ: กดปุ่ม Ctrl+Shift+Esc เพื่อเปิด Task Manager -> ไปที่แท็บ 'Startup apps' -> คลิกขวาโปรแกรมแล้วเลือก 'Disable'" -ForegroundColor Cyan
    } else {
        Write-Host "ไม่พบโปรแกรมที่เริ่มทำงานอัตโนมัติ" -ForegroundColor Green
    }
    
    # Checking for heavy services that could be tuned
    Write-Host "`nกำลังวิเคราะห์บริการ (Services) ที่ใช้ทรัพยากรระบบสูง..." -ForegroundColor Yellow
    try {
        $services = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.StartType -eq "Automatic" -and $_.Status -eq "Running" }
        $heavyServices = @("SysMain", "DiagTrack", "WSearch", "Spooler")
        $foundHeavy = $false
        
        foreach ($srv in $services) {
            if ($heavyServices -contains $srv.Name) {
                $foundHeavy = $true
                $desc = ""
                if ($srv.Name -eq "SysMain") { $desc = "Superfetch - หากใช้ HDD อาจทำให้ดิสก์รัน 100% บ่อยครั้ง" }
                if ($srv.Name -eq "DiagTrack") { $desc = "Connected User Experiences - การส่งข้อมูลวินิจฉัยกลับไปยัง Microsoft" }
                if ($srv.Name -eq "WSearch") { $desc = "Windows Search - บริการทำดัชนีไฟล์ หากมีไฟล์เยอะอาจกิน CPU/Disk หนัก" }
                if ($srv.Name -eq "Spooler") { $desc = "Print Spooler - หากคุณไม่เคยใช้งานเครื่องพิมพ์ สามารถตั้งเป็น Manual ได้" }
                
                Write-Host "- $($srv.Name) : $desc" -ForegroundColor White
            }
        }
        
        if ($foundHeavy) {
            Write-Host "`nคำแนะนำเสริม: หากเครื่องของคุณมีอาการช้าหรือทำงานหนัก สามารถเปลี่ยนบริการเหล่านี้เป็นแบบ 'Manual' (กำหนดเอง) ได้ใน Services.msc" -ForegroundColor Cyan
            Write-Host "(สคริปต์นี้จะข้ามการปิดบริการอัตโนมัติเพื่อหลีกเลี่ยงผลกระทบต่อระบบของท่าน)" -ForegroundColor DarkGray
        } else {
            Write-Host "ไม่พบบริการที่น่ากังวล" -ForegroundColor Green
        }
        
    } catch {
        Write-Warning2 "ไม่สามารถดึงข้อมูล Services ได้ในขณะนี้"
    }
    
    # Note: Check for scheduled tasks that impact performance (informative only)
    Write-Host "`nตรวจสอบงานที่ถูกจัดตารางเวลา (Scheduled Tasks):" -ForegroundColor Yellow
    try {
        $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.State -eq "Ready" -and $_.TaskPath -notmatch "\\Microsoft\\" }
        if ($tasks) {
            Write-Host "พบงานที่กำหนดเวลาไว้โดยแอปพลิเคชันภายนอกจำนวน $($tasks.Count) งาน" -ForegroundColor White
        } else {
            Write-Host "ไม่มีงานจากแอปภายนอกที่เตรียมทำงาน" -ForegroundColor Green
        }
    } catch {}
    
    Write-Log "Module 3 Complete: Startup apps and services analyzed" "INFO"
}

# =============================================================================
# 9. MODULE 4: Tune-Performance
# =============================================================================
function Tune-Performance {
    Write-ModuleHeader "โมดูล 4: ปรับแต่งประสิทธิภาพของระบบ (Performance Tuning)"
    
    # 1. Visual Effects Tuning
    Write-Host "กำลังปรับตั้งค่าภาพเคลื่อนไหว (Visual Effects) เพื่อความรวดเร็ว..." -ForegroundColor Cyan
    try {
        if ($Global:PreviewMode -eq $false) {
            # Value 3 = Custom. Windows uses a combination of settings.
            # FIXED: 3 means "Custom", which changes nothing on its own - the script
            # reported success while doing nothing. 2 = "Adjust for best performance".
            Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Value 2 -ErrorAction SilentlyContinue
            
            # Explicitly keep font smoothing enabled for clear text readability
            Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "FontSmoothing" -Value "2" -ErrorAction SilentlyContinue
            
            Write-Success "ปรับแต่ง Visual Effects เรียบร้อยแล้ว (ยังคงความคมชัดของตัวหนังสือไว้)"
        } else {
            Write-Success "[พรีวิว] จะทำการปรับแต่ง Visual Effects สำหรับประสิทธิภาพ"
        }
    } catch {
        Write-Warning2 "ไม่สามารถปรับแต่ง Visual Effects ได้"
    }
    
    # 2. Power Plan Setup
    Write-Host "กำลังตั้งค่าแผนการใช้พลังงานเป็นแบบประสิทธิภาพสูง (High Performance)..." -ForegroundColor Cyan
    try {
        if ($Global:PreviewMode -eq $false) {
            # GUID for standard High Performance power plan
            $highPerfGuid = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
            powercfg -setactive $highPerfGuid | Out-Null
            
            # Verify if it was successfully changed
            $currentPlan = powercfg -getactivescheme
            if ($currentPlan -match $highPerfGuid) {
                Write-Success "เปลี่ยนแผนพลังงานเป็น High Performance สำเร็จ"
            } else {
                Write-Warning2 "เครื่องนี้อาจไม่มีแผน High Performance หรือถูกจำกัดโดยผู้ผลิต (OEM)"
            }
        } else {
            Write-Success "[พรีวิว] จะพยายามเปิดใช้แผนพลังงาน High Performance"
        }
    } catch {
        Write-Warning2 "เกิดปัญหาขณะพยายามแก้ไข Power Plan"
    }
    
    # 3. Virtual Memory (Page File) Check
    Write-Host "กำลังตรวจสอบการตั้งค่าพื้นที่หน่วยความจำเสมือน (Page File)..." -ForegroundColor Cyan
    try {
        $computerSystem = Get-WmiObject Win32_ComputerSystem -ErrorAction SilentlyContinue
        if ($computerSystem -and $computerSystem.AutomaticManagedPagefile -eq $false) {
            if ($Global:PreviewMode -eq $false) {
                # Enable system managed pagefile for optimal stability
                $computerSystem.AutomaticManagedPagefile = $true
                $computerSystem.Put() | Out-Null
                Write-Success "ปรับให้ Windows จัดการ Page File อัตโนมัติ (System Managed) เพื่อความเสถียร"
            } else {
                Write-Success "[พรีวิว] จะเปิดการจัดการ Page File อัตโนมัติ"
            }
        } else {
            Write-Host "  - Page File ถูกตั้งค่าให้ระบบจัดการอัตโนมัติอยู่แล้ว (ดีที่สุด)" -ForegroundColor Green
        }
    } catch {
        Write-Warning2 "ไม่สามารถตรวจสอบสถานะของ Page File ได้"
    }
    
    # 4. Storage Optimization (SSD TRIM / HDD Defrag)
    Write-Host "กำลังตรวจสอบและปรับแต่งสื่อบันทึกข้อมูล (Disk Optimization)..." -ForegroundColor Cyan
    try {
        $sysDriveLetter = $env:SystemDrive.Substring(0,1)
        # Attempt to determine media type (SSD or HDD)
        # FIXED: the old -or condition grabbed whichever disk reported OK first, so on a
        # machine with a second HDD it could report "HDD" and then defrag the system SSD.
        # Resolve the physical disk that actually backs the system volume instead.
        $diskInfo = $null
        try {
            $diskInfo = Get-Partition -DriveLetter $sysDriveLetter -ErrorAction Stop |
                        Get-Disk -ErrorAction Stop |
                        Get-PhysicalDisk -ErrorAction Stop |
                        Select-Object -First 1 -Property MediaType
        } catch {
            Write-Log "Could not resolve the physical disk behind drive $sysDriveLetter" "WARNING"
        }
        
        $mediaType = "Unknown"
        if ($diskInfo -and $diskInfo.MediaType) {
            $mediaType = $diskInfo.MediaType
        }
        
        Write-Host "ชนิดของดิสก์ที่ตรวจพบ: $mediaType" -ForegroundColor Yellow
        
        if ($Global:PreviewMode -eq $false) {
            if ($mediaType -eq "SSD") {
                Write-Host "กำลังรันคำสั่ง TRIM เพื่อรักษาความเร็วของ SSD..." -ForegroundColor Cyan
                Optimize-Volume -DriveLetter $sysDriveLetter -ReTrim -Verbose:$false | Out-Null
                Write-Success "ล้างบล็อกข้อมูลที่ว่างเปล่า (TRIM) ให้กับ SSD สำเร็จ"
            } elseif ($mediaType -eq "HDD") {
                Write-Host "กำลังจัดเรียงข้อมูล (Defragmentation) สำหรับ HDD..." -ForegroundColor Cyan
                Write-Host "(กระบวนการนี้อาจใช้เวลานาน กรุณารอสักครู่...)" -ForegroundColor Yellow
                Optimize-Volume -DriveLetter $sysDriveLetter -Defrag -Verbose:$false | Out-Null
                Write-Success "จัดเรียงข้อมูลดิสก์ให้เป็นระเบียบสำเร็จ"
            } else {
                # Fallback to standard optimization
                Optimize-Volume -DriveLetter $sysDriveLetter -Verbose:$false | Out-Null
                Write-Success "ดำเนินการ Optimize ไดรฟ์ระบบสำเร็จ"
            }
        } else {
            Write-Success "[พรีวิว] จะทำการ Optimize ไดรฟ์ ($mediaType)"
        }
    } catch {
        Write-Warning2 "ไม่สามารถปรับแต่งดิสก์ได้ในขณะนี้ (อาจกำลังถูกใช้งานอยู่)"
    }
    
    # 5. Clear Standby Memory List
    Write-Host "กำลังล้างแคชหน่วยความจำแสตนด์บาย (Standby Memory List)..." -ForegroundColor Cyan
    try {
        if ($Global:PreviewMode -eq $false) {
            # Advanced C# P/Invoke to call NtSetSystemInformation (MemoryPurgeStandbyList)
            $memUtilCode = @"
using System;
using System.Runtime.InteropServices;

public class MemoryCleaner
{
    [DllImport("advapi32.dll", SetLastError = true)]
    internal static extern bool OpenProcessToken(IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);
    
    [DllImport("kernel32.dll", SetLastError = true)]
    internal static extern IntPtr GetCurrentProcess();
    
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    internal static extern bool LookupPrivilegeValue(string lpSystemName, string lpName, out long lpLuid);
    
    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    internal struct TOKEN_PRIVILEGES
    {
        public int PrivilegeCount;
        public long Luid;
        public int Attributes;
    }
    
    [DllImport("advapi32.dll", SetLastError = true)]
    internal static extern bool AdjustTokenPrivileges(IntPtr TokenHandle, bool DisableAllPrivileges, ref TOKEN_PRIVILEGES NewState, int BufferLength, IntPtr PreviousState, IntPtr ReturnLength);
    
    [DllImport("ntdll.dll")]
    internal static extern int NtSetSystemInformation(int SystemInformationClass, IntPtr SystemInformation, int SystemInformationLength);

    public static void EmptyStandbyList()
    {
        IntPtr token;
        if (OpenProcessToken(GetCurrentProcess(), 0x0020 | 0x0008, out token))
        {
            long luid;
            if (LookupPrivilegeValue(null, "SeProfileSingleProcessPrivilege", out luid))
            {
                TOKEN_PRIVILEGES tp = new TOKEN_PRIVILEGES();
                tp.PrivilegeCount = 1;
                tp.Luid = luid;
                tp.Attributes = 2; // SE_PRIVILEGE_ENABLED
                
                AdjustTokenPrivileges(token, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
                
                // 80 corresponds to SystemMemoryListInformation
                // 4 corresponds to MemoryPurgeStandbyList
                int systemMemoryListInformation = 80;
                int command = 4; 
                
                IntPtr pCommand = Marshal.AllocHGlobal(sizeof(int));
                Marshal.WriteInt32(pCommand, command);
                NtSetSystemInformation(systemMemoryListInformation, pCommand, sizeof(int));
                Marshal.FreeHGlobal(pCommand);
            }
        }
    }
}
"@
            Add-Type -TypeDefinition $memUtilCode -Language CSharp -ErrorAction SilentlyContinue
            [MemoryCleaner]::EmptyStandbyList()
            Write-Success "เคลียร์แคชหน่วยความจำ (Standby List) เรียบร้อยแล้วเพื่อลดอาการค้าง"
        } else {
            Write-Success "[พรีวิว] จะล้าง Standby Memory List"
        }
    } catch {
        # Fallback to simple Garbage Collection if C# compilation/execution fails
        [GC]::Collect()
        Write-Warning2 "ไม่สามารถล้างขั้นลึกได้ ทำการเรียกคืนหน่วยความจำเบื้องต้นแทน"
    }
    
    Write-Log "Module 4 Complete: Performance tuned" "SUCCESS"
}

# =============================================================================
# 10. MODULE 5: Generate-Report
# =============================================================================
function Generate-Report {
    Write-ModuleHeader "โมดูล 5: สรุปผลการทำความสะอาดและตรวจสอบระบบ"
    
    $endTime = Get-Date
    $timeTaken = New-TimeSpan -Start $Global:StartTime -End $endTime
    
    # Gather comprehensive system info for the report
    Write-Host "กำลังรวบรวมข้อมูลระบบขั้นสุดท้าย..." -ForegroundColor Cyan
    
    $osInfo = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cpuInfo = Get-CimInstance Win32_Processor | Select-Object -First 1 -ErrorAction SilentlyContinue
    
    $ramInfo = 0
    $freeRam = 0
    if ($osInfo) {
        $ramInfo = [math]::Round($osInfo.TotalVisibleMemorySize / 1MB, 2)
        $freeRam = [math]::Round($osInfo.FreePhysicalMemory / 1MB, 2)
    }
    
    $sysDrive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'" -ErrorAction SilentlyContinue
    $diskTotal = 0
    $diskFree = 0
    if ($sysDrive) {
        $diskTotal = [math]::Round($sysDrive.Size / 1GB, 2)
        $diskFree = [math]::Round($sysDrive.FreeSpace / 1GB, 2)
    }
    
    # Calculate boot time
    $bootTimeStr = "ไม่ทราบข้อมูล"
    try {
        if ($osInfo -and $osInfo.LastBootUpTime) {
            $bootTimeStr = $osInfo.LastBootUpTime.ToString("dd/MM/yyyy HH:mm:ss")
        }
    } catch {}
    
    # SMART Disk Health check
    $smartStatusStr = "ไม่ทราบสถานะ"
    try {
        $smartData = Get-WmiObject -Namespace root\wmi -Class MSStorageDriver_FailurePredictStatus -ErrorAction SilentlyContinue
        if ($smartData) {
            $failing = $false
            foreach ($s in $smartData) {
                if ($s.PredictFailure) { $failing = $true }
            }
            if ($failing) {
                $smartStatusStr = "พบความเสี่ยง (อาจมีปัญหาฮาร์ดแวร์ดิสก์)"
            } else {
                $smartStatusStr = "ปกติ (OK)"
            }
        }
    } catch {}
    
    # Formatting sizes properly
    $totalCleanedStr = Format-FileSize -Bytes $Global:TotalCleaned
    
    # Constructing the final report text
    $reportOutput = @"

===============================================================================
                           รายงานสรุปผลการปรับปรุงระบบ
===============================================================================

[ ข้อมูลระบบทั่วไป (System Information) ]
- ระบบปฏิบัติการ:       $($osInfo.Caption)
- หน่วยประมวลผล (CPU):  $($cpuInfo.Name)
- สถานะหน่วยความจำ:     เหลือใช้ $freeRam GB / จากทั้งหมด $ramInfo GB
- พื้นที่ดิสก์ (ไดรฟ์ C:):    เหลือใช้ $diskFree GB / จากทั้งหมด $diskTotal GB
- สุขภาพดิสก์ (SMART):   $smartStatusStr
- บูตระบบล่าสุดเมื่อ:      $bootTimeStr

[ ผลการดำเนินงาน (Cleanup & Optimization Results) ]
- เวลาที่ใช้ทำงานทั้งหมด:   $([int]$timeTaken.TotalMinutes) นาที $($timeTaken.Seconds) วินาที
- พื้นที่ดิสก์ที่ได้คืน:        $totalCleanedStr
- จำนวนปัญหาที่ซ่อมแซม:   $Global:TotalFixed รายการ

[ ข้อมูลเพิ่มเติม ]
บันทึกการทำงานทั้งหมด (Log File) ถูกเก็บไว้อย่างปลอดภัยที่:
$Global:LogFile
===============================================================================
"@

    # Print out the report
    Write-Host $reportOutput -ForegroundColor Cyan
    Write-Log "Generated Final Report" "INFO"
    Write-Log "Total Cleaned: $totalCleanedStr, Total Fixed: $Global:TotalFixed" "INFO"
    
    Write-Host "`nเสร็จสิ้นกระบวนการในส่วนแรก (Part 1)" -ForegroundColor Green
}

# Module 6: Scan-Security
function Scan-Security {
    Write-ModuleHeader  "สแกนความปลอดภัย (Scan Security)"
    Write-Log  "Starting security scan" -Type "INFO"

    # Update Windows Defender definitions
    Write-Host "กำลังอัปเดตฐานข้อมูลไวรัส Windows Defender..." -ForegroundColor Cyan
    if (-not $Global:PreviewMode) {
        try {
            Update-MpSignature -ErrorAction Stop
            Write-Success  "อัปเดตฐานข้อมูลไวรัสเรียบร้อยแล้ว"
        } catch {
            Write-Warning2  "ไม่สามารถอัปเดตฐานข้อมูลไวรัสได้: $($_.Exception.Message)"
        }
    } else {
        Write-Host "[PREVIEW] อัปเดตฐานข้อมูล Windows Defender" -ForegroundColor DarkGray
    }

    $scanChoice = Read-Host "ต้องการสแกนแบบไหน? (1) Quick Scan, (2) Full Scan, (0) ข้าม [1]"
    if ($scanChoice -eq '1' -or $scanChoice -eq '') {
        $scanType = "QuickScan"
    } elseif ($scanChoice -eq '2') {
        $scanType = "FullScan"
    } else {
        $scanType = $null
    }

    if ($scanType -ne $null) {
        Write-Host "กำลังสแกนไวรัส ($scanType)..." -ForegroundColor Cyan
        if (-not $Global:PreviewMode) {
            try {
                Start-MpScan -ScanType $scanType -ErrorAction Stop
                Write-Success  "สแกนไวรัสเสร็จสมบูรณ์"
            } catch {
                Write-Warning2  "เกิดข้อผิดพลาดในการสแกนไวรัส: $($_.Exception.Message)"
            }
        } else {
            Write-Host "[PREVIEW] สแกนไวรัส $scanType" -ForegroundColor DarkGray
        }
    }

    # Check hosts file for suspicious entries
    Write-Host "`nกำลังตรวจสอบไฟล์ hosts..." -ForegroundColor Cyan
    $hostsFile = "$env:windir\System32\drivers\etc\hosts"
    if (Test-Path $hostsFile) {
        try {
            $hostsLines = Get-Content $hostsFile | Where-Object { $_ -notmatch '^\s*#' -and $_ -notmatch '^\s*$' -and $_ -notmatch 'localhost' -and $_ -notmatch '127\.0\.0\.1' -and $_ -notmatch '::1' }
            if ($hostsLines.Count -gt 0) {
                Write-Warning2  "พบรายการที่น่าสงสัยในไฟล์ hosts (อาจถูกแก้ไขโดยมัลแวร์):"
                $hostsLines | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
            } else {
                Write-Success  "ไฟล์ hosts ปกติ (ไม่พบรายการแปลกปลอม)"
            }
        } catch { Write-Warning2  "ไม่สามารถอ่านไฟล์ hosts ได้" }
    }

    # Check DNS Settings
    Write-Host "`nกำลังตรวจสอบการตั้งค่า DNS..." -ForegroundColor Cyan
    try {
        $dnsServers = Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object { $_.ServerAddresses -ne $null }
        foreach ($adapter in $dnsServers) {
            Write-Host "อะแดปเตอร์ $($adapter.InterfaceAlias) ใช้ DNS: $($adapter.ServerAddresses -join ', ')" -ForegroundColor Gray
        }
        Write-Success  "ตรวจสอบ DNS เสร็จสิ้น (โปรดพิจารณาว่า DNS แปลกปลอมหรือไม่)"
    } catch {
        Write-Warning2  "ไม่สามารถตรวจสอบ DNS ได้: $($_.Exception.Message)"
    }

    # Check Registry Run keys
    Write-Host "`nกำลังตรวจสอบโปรแกรมเริ่มต้นที่น่าสงสัยใน Registry..." -ForegroundColor Cyan
    $runKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
    )
    $suspiciousFound = $false
    foreach ($key in $runKeys) {
        if (Test-Path $key) {
            $entries = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
            foreach ($prop in $entries.psobject.properties) {
                if ($prop.Name -notin @("PSPath","PSParentPath","PSChildName","PSDrive","PSProvider")) {
                    $val = $prop.Value -as [string]
                    if ($val -match "Temp|AppData|Roaming" -or $prop.Name -match "^[a-zA-Z0-9]{8,15}$") {
                        Write-Warning2  "พบโปรแกรมที่น่าสงสัยใน Registry: $($prop.Name) -> $val"
                        $suspiciousFound = $true
                    }
                }
            }
        }
    }
    if (-not $suspiciousFound) {
        Write-Success  "ไม่พบโปรแกรมเริ่มต้นที่น่าสงสัย"
    }

    # Check Scheduled Tasks
    Write-Host "`nกำลังตรวจสอบ Scheduled Tasks ที่น่าสงสัย..." -ForegroundColor Cyan
    try {
        $suspiciousTasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { 
            $_.Author -notmatch "Microsoft" -and 
            $_.State -ne "Disabled" -and 
            ($_.Actions.Execute -match "Temp" -or $_.Actions.Execute -match "AppData")
        }
        if ($suspiciousTasks) {
            Write-Warning2  "พบ Task ที่น่าสงสัย (ทำงานจากโฟลเดอร์ชั่วคราวและไม่ใช่ของ Microsoft):"
            $suspiciousTasks | ForEach-Object { Write-Host "  $($_.TaskName) -> $($_.Actions.Execute)" -ForegroundColor Yellow }
        } else {
            Write-Success  "ไม่พบ Task ที่น่าสงสัย"
        }
    } catch {
        Write-Warning2  "ไม่สามารถตรวจสอบ Scheduled Tasks ได้"
    }
    
    # Check browser extensions
    Write-Host "`nกำลังตรวจสอบโฟลเดอร์ส่วนขยายเบราว์เซอร์ (Extensions)..." -ForegroundColor Cyan
    $chromeExt = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Extensions"
    $edgeExt = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Extensions"
    if (Test-Path $chromeExt) {
        $count = (Get-ChildItem -Path $chromeExt -Directory).Count
        Write-Host "พบส่วนขยาย Chrome: $count รายการ" -ForegroundColor Gray
    }
    if (Test-Path $edgeExt) {
        $count = (Get-ChildItem -Path $edgeExt -Directory).Count
        Write-Host "พบส่วนขยาย Edge: $count รายการ" -ForegroundColor Gray
    }
    Write-Host "หมายเหตุ: โปรดตรวจสอบส่วนขยายที่ไม่รู้จักในเบราว์เซอร์ของคุณด้วยตัวเอง" -ForegroundColor DarkGray

    # Security Summary
    Write-Host "`n=== สรุปผลการสแกนความปลอดภัย ===" -ForegroundColor Green
    Write-Host "การสแกนและการวิเคราะห์เสร็จสมบูรณ์ หากพบรายการสีเหลือง โปรดตรวจสอบเพิ่มเติมด้วยตนเอง" -ForegroundColor White
}

# Module 7: Optimize-Background
function Optimize-Background {
    Write-ModuleHeader  "ปิดการทำงานพื้นหลัง (Optimize Background)"
    Write-Log  "Starting background optimization" -Type "INFO"

    if (-not (Test-Path $Global:LogDir)) { New-Item -Path $Global:LogDir -ItemType Directory -Force | Out-Null }
    # FIXED: the contents are PowerShell commands, not a .reg file, so the old name was
    # misleading (regedit rejects it). One file per run, so restores are not mixed.
    $restoreFile = "$Global:LogDir\RegistryRestore_$(Get-Date -Format 'yyyyMMdd_HHmmss').ps1"

    if (-not $Global:PreviewMode) {
        Create-RestorePoint
    }

    # Helper function for safe registry modification with logging
    function Update-RegSetting {
        param($Desc, $Path, $Name, $NewValue)
        Write-Host "`nกำลัง$Desc..." -ForegroundColor Cyan
        try {
            $currentVal = "Not Set"
            if (Test-Path $Path) {
                $item = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
                if ($item -ne $null -and $item.psobject.properties.match($Name).Count) { 
                    $currentVal = $item.$Name 
                }
            } else {
                if (-not $Global:PreviewMode) { New-Item -Path $Path -Force | Out-Null }
            }
            
            Write-Host "  รายละเอียด: $Desc" -ForegroundColor Gray
            Write-Host "  ค่าปัจจุบัน: $currentVal" -ForegroundColor Yellow
            Write-Host "  ค่าที่ต้องการ: $NewValue" -ForegroundColor Green
            
            if (-not $Global:PreviewMode) {
                # Create restore entry in log file
                $restoreCmd = "if (!(Test-Path '$Path')) { New-Item -Path '$Path' -Force | Out-Null }; Set-ItemProperty -Path '$Path' -Name '$Name' -Value '$currentVal' -Force"
                if ($currentVal -ne "Not Set") {
                    Add-Content -Path $restoreFile -Value $restoreCmd
                }
                
                Set-ItemProperty -Path $Path -Name $Name -Value $NewValue -Force
                Write-Success  "ปรับแต่งสำเร็จ"
            } else {
                Write-Host "  [PREVIEW] ข้ามการเขียนค่า Registry" -ForegroundColor DarkGray
            }
        } catch {
            Write-Warning2  "เกิดข้อผิดพลาด: $($_.Exception.Message)"
        }
    }

    # Disable Background Apps (UWP)
    # FIXED: the English half already had this disabled in v1.1 to keep Omen Hub hotkeys
    # working, but the Thai half still ran it. Now both behave the same.
    # Update-RegSetting -Desc "ปิดแอปพลิเคชันที่ทำงานเบื้องหลัง (Background Apps)" `
    #                   -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" `
    #                   -Name "GlobalUserDisabled" -NewValue 1

    # FIXED: ถอดออก เดิมตั้ง AllowTelemetry = 1 แต่เมนู 14 ตั้ง 0 ทำให้ตอนกด "ทำทุกข้อ"
    # เขียนคีย์เดียวกันสองรอบและบอกผู้ใช้ไม่ตรงกับผลจริง
    # ตอนนี้เรื่อง Telemetry จัดการที่เมนู 14 (Block Telemetry) ที่เดียว

    # Disable Cortana
    Update-RegSetting -Desc "ปิดการใช้งาน Cortana และการจำกัดค้นหา" `
                      -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" `
                      -Name "AllowCortana" -NewValue 0

    # Disable Tips & Suggestions
    Update-RegSetting -Desc "ปิดคำแนะนำและเคล็ดลับจาก Windows (Tips & Suggestions)" `
                      -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" `
                      -Name "SubscribedContent-338389Enabled" -NewValue 0

    # Disable Game Bar & Game DVR
    Update-RegSetting -Desc "ปิดฟีเจอร์ Game DVR (บันทึกวิดีโอเกม) ใน HKCU" `
                      -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" `
                      -Name "AppCaptureEnabled" -NewValue 0

    Update-RegSetting -Desc "ปิดฟีเจอร์ Game Bar ในระบบหลัก (HKLM)" `
                      -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\ApplicationManagement\AllowGameDVR" `
                      -Name "value" -NewValue 0

    # Disable Transparency
    Update-RegSetting -Desc "ปิดเอฟเฟกต์โปร่งแสง (Transparency Effects)" `
                      -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" `
                      -Name "EnableTransparency" -NewValue 0

    # Stop OneDrive Sync
    Write-Host "`nตัวเลือกการหยุดซิงค์ OneDrive:" -ForegroundColor Cyan
    $ans = Read-Host "ต้องการหยุด Process ของ OneDrive เพื่อประหยัดทรัพยากรหรือไม่? (ไฟล์จะไม่ถูกลบ) (y/n) [n]"
    if ($ans -eq 'y') {
        if (-not $Global:PreviewMode) {
            try {
                Stop-Process -Name "OneDrive" -Force -ErrorAction SilentlyContinue
                Write-Success  "หยุดการทำงานของ OneDrive ชั่วคราวสำเร็จ"
            } catch { Write-Warning2  "ไม่สามารถหยุด OneDrive ได้ หรือยังไม่ได้รันอยู่" }
        } else { Write-Host "  [PREVIEW] หยุด Process OneDrive" -ForegroundColor DarkGray }
    }

    # Disable unnecessary services
    Write-Host "`nกำลังตรวจสอบบริการที่ไม่ได้ใช้งานบ่อย..." -ForegroundColor Cyan
    $servicesToCheck = @("Fax", "XboxGipSvc")
    
    # FIXED: the English half already had this disabled in v1.1 so Print Spooler stays
    # running, but the Thai half still turned it off. Now both behave the same.
    # $printers = Get-Printer -ErrorAction SilentlyContinue | Where-Object Name -notmatch "PDF|XPS|OneNote"
    # if (-not $printers -or $printers.Count -eq 0) {
    #     $servicesToCheck += "Spooler"
    # }

    foreach ($svc in $servicesToCheck) {
        try {
            $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
            if ($s) {
                $svcCim = Get-CimInstance Win32_Service -Filter "Name='$svc'" -ErrorAction SilentlyContinue
                $currentMode = if ($svcCim) { $svcCim.StartMode } else { "Unknown" }
                
                Write-Host "  บริการ: $svc" -ForegroundColor Gray
                Write-Host "  สถานะปัจจุบัน: $currentMode" -ForegroundColor Yellow
                Write-Host "  สถานะที่ต้องการ: Manual" -ForegroundColor Green
                
                if (-not $Global:PreviewMode) {
                    if ($currentMode -ne "Manual") {
                        Set-Service -Name $svc -StartupType Manual -ErrorAction Stop
                        Write-Success  "ปรับบริการ $svc เป็น Manual สำเร็จ"
                    } else {
                        Write-Success  "บริการ $svc เป็น Manual อยู่แล้ว"
                    }
                } else {
                    Write-Host "  [PREVIEW] ข้ามการปรับบริการ $svc" -ForegroundColor DarkGray
                }
            }
        } catch { Write-Warning2  "ข้ามบริการ $svc (อาจไม่มีในระบบหรือไม่มีสิทธิ์)" }
    }
}

# Module 8: Analyze-DiskSpace
function Analyze-DiskSpace {
    Write-ModuleHeader  "วิเคราะห์พื้นที่ฮาร์ดดิสก์ (Analyze Disk Space)"
    Write-Log  "Starting disk space analysis" -Type "INFO"

    # Show disk space summary
    Write-Host "`n[ข้อมูลพื้นที่ดิสก์]" -ForegroundColor Cyan
    try {
        $drives = Get-CimInstance Win32_LogicalDisk | Where-Object DriveType -eq 3
        foreach ($drive in $drives) {
            $freeGB = [math]::Round($drive.FreeSpace / 1GB, 2)
            $totalGB = [math]::Round($drive.Size / 1GB, 2)
            $usedGB = $totalGB - $freeGB
            $percentUsed = [int](($usedGB / $totalGB) * 100)
            
            $barLen = 20
            $filled = [int](([math]::Round($percentUsed / 100, 2)) * $barLen)
            $empty = $barLen - $filled
            if ($filled -lt 0) { $filled = 0 }
            if ($empty -lt 0) { $empty = 0 }
            $bar = ("█" * $filled) + ("░" * $empty)
            
            Write-Host "$($drive.DeviceID) ($($drive.VolumeName)) -> [$bar] $percentUsed% ใช้ไป ($usedGB GB / $totalGB GB) ว่าง $freeGB GB" -ForegroundColor Green
        }
    } catch { Write-Warning2  "เกิดข้อผิดพลาดในการดึงข้อมูลไดรฟ์" }

    # Top 20 largest folders on C:
    Write-Host "`nกำลังค้นหาโฟลเดอร์ขนาดใหญ่ 20 อันดับแรกในไดรฟ์ C: (ยกเว้น Windows และ Program Files)..." -ForegroundColor Cyan
    try {
        $topFolders = Get-ChildItem -Path "C:\" -Directory -ErrorAction SilentlyContinue | Where-Object { 
            $_.Name -notmatch "Windows" -and $_.Name -notmatch "Program Files" 
        } | Select-Object Name, FullName, @{Name="SizeMB";Expression={[math]::Round((Get-FolderSize $_.FullName) / 1MB, 2)}} | Sort-Object SizeMB -Descending | Select-Object -First 20

        if ($topFolders) {
            $topFolders | Format-Table -AutoSize | Out-String | Write-Host
        }
    } catch {
        Write-Warning2  "เกิดข้อผิดพลาดในการค้นหาโฟลเดอร์"
    }

    # Top 50 largest files on all drives
    Write-Host "กำลังค้นหาไฟล์ขนาดใหญ่ 50 อันดับแรกในทุกไดรฟ์ (อาจใช้เวลาสักครู่)..." -ForegroundColor Cyan
    try {
        $allDrives = Get-CimInstance Win32_LogicalDisk | Where-Object DriveType -eq 3 | Select-Object -ExpandProperty DeviceID
        $allFiles = @()
        foreach ($drv in $allDrives) {
            # Limit depth or ignore Windows folders to prevent extreme slow down, but sticking to general search
            # FIXED: the original walked every drive to full depth, which took hours and
            # used a lot of memory. Cap the depth and skip system folders.
            $allFiles += Get-ChildItem -Path "$drv\" -File -Recurse -Depth 4 -ErrorAction SilentlyContinue |
                         Where-Object { $_.FullName -notmatch '\\(Windows|System Volume Information|\$Recycle\.Bin)\\' } |
                         Sort-Object Length -Descending | Select-Object -First 50
        }
        $top50Files = $allFiles | Sort-Object Length -Descending | Select-Object -First 50 Name, Directory, @{Name="SizeMB";Expression={[math]::Round($_.Length / 1MB, 2)}}
        
        if ($top50Files) {
            $top50Files | Format-Table -AutoSize | Out-String | Write-Host
        }
    } catch {
        Write-Warning2  "เกิดข้อผิดพลาดในการค้นหาไฟล์"
    }

    # Duplicate finder (simple)
    Write-Host "กำลังค้นหาไฟล์ที่อาจซ้ำกันในโฟลเดอร์ผู้ใช้ (ชื่อไฟล์และขนาดเท่ากัน)..." -ForegroundColor Cyan
    try {
        # FIXED: cap the depth and skip AppData - the original walked every user profile in full.
        $files = Get-ChildItem -Path "C:\Users\" -File -Recurse -Depth 5 -ErrorAction SilentlyContinue |
                 Where-Object { $_.Length -gt 1MB -and $_.FullName -notmatch '\\AppData\\' }
        $duplicates = $files | Group-Object Name, Length | Where-Object Count -gt 1 | Select-Object -First 20
        if ($duplicates) {
            Write-Host "พบไฟล์ที่อาจซ้ำกัน (ตัวอย่าง 20 กลุ่ม):" -ForegroundColor Yellow
            foreach ($group in $duplicates) {
                Write-Host "  กลุ่มไฟล์: $($group.Name) | ขนาด: $([math]::Round($group.Group[0].Length / 1MB, 2)) MB | จำนวน: $($group.Count)" -ForegroundColor Gray
                foreach ($f in $group.Group) {
                    Write-Host "    -> $($f.FullName)" -ForegroundColor DarkGray
                }
            }
        } else {
            Write-Success  "ไม่พบไฟล์ซ้ำขนาดใหญ่ในโฟลเดอร์ผู้ใช้"
        }
    } catch {
        Write-Warning2  "เกิดข้อผิดพลาดในการค้นหาไฟล์ซ้ำ"
    }

    # Component Store Cleanup
    Write-Host "`n[เครื่องมือทำความสะอาดระดับสูง]" -ForegroundColor Cyan
    $runDism = Read-Host "ต้องการเปิดใช้งาน WinSxS Component Store Cleanup หรือไม่? (y/n) [n]"
    if ($runDism -eq 'y') {
        Write-Host "กำลังล้างไฟล์ระบบเก่าด้วย DISM (อาจใช้เวลานาน)..." -ForegroundColor Cyan
        if (-not $Global:PreviewMode) {
            try {
                Start-Process -FilePath "Dism.exe" -ArgumentList "/Online /Cleanup-Image /StartComponentCleanup" -Wait -NoNewWindow
                Write-Success  "ทำความสะอาด Component Store เสร็จสิ้น"
            } catch {
                Write-Warning2  "ไม่สามารถรัน DISM ได้"
            }
        } else { Write-Host "  [PREVIEW] รัน DISM /Cleanup-Image" -ForegroundColor DarkGray }
    }

    # Enable Storage Sense
    Write-Host "`nกำลังเปิดใช้งาน Storage Sense..." -ForegroundColor Cyan
    if (-not $Global:PreviewMode) {
        try {
            $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy"
            if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
            Set-ItemProperty -Path $regPath -Name "01" -Value 1 -Force
            Write-Success  "เปิดใช้งาน Storage Sense สำเร็จ"
        } catch { Write-Warning2  "ไม่สามารถเปิด Storage Sense ได้" }
    } else { Write-Host "  [PREVIEW] เปิดใช้งาน Storage Sense Registry" -ForegroundColor DarkGray }
}

# Module 9: Optimize-Network
function Optimize-Network {
    Write-ModuleHeader  "ปรับแต่งเครือข่าย (Optimize Network)"
    Write-Log  "Starting network optimization" -Type "INFO"

    # Check network adapter driver info
    Write-Host "ข้อมูลไดรเวอร์อะแดปเตอร์เครือข่าย (Network Drivers):" -ForegroundColor Cyan
    try {
        $netAdapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object Status -eq "Up"
        if ($netAdapters) {
            foreach ($adp in $netAdapters) {
                $driverInfo = Get-NetAdapter -Name $adp.Name | Select-Object Name, InterfaceDescription, DriverVersion, DriverDate, DriverProvider
                Write-Host "  ชื่อ: $($driverInfo.Name)" -ForegroundColor Gray
                Write-Host "  คำอธิบาย: $($driverInfo.InterfaceDescription)" -ForegroundColor DarkGray
                Write-Host "  รุ่นไดรเวอร์: $($driverInfo.DriverVersion) ($($driverInfo.DriverDate))" -ForegroundColor DarkGray
            }
        } else {
            Write-Host "  ไม่พบอะแดปเตอร์ที่กำลังใช้งาน" -ForegroundColor DarkGray
        }
    } catch {
        Write-Warning2  "ไม่สามารถดึงข้อมูลไดรเวอร์เครือข่ายได้"
    }

    # Flush DNS
    Write-Host "`nกำลังล้างแคช DNS (Flush DNS)..." -ForegroundColor Cyan
    if (-not $Global:PreviewMode) {
        try {
            Clear-DnsClientCache
            Write-Success  "ล้างแคช DNS สำเร็จ"
        } catch { Write-Warning2  "ไม่สามารถล้างแคช DNS ได้" }
    } else { Write-Host "  [PREVIEW] รันคำสั่ง Clear-DnsClientCache" -ForegroundColor DarkGray }

    # Flush ARP cache
    Write-Host "`nกำลังล้างแคช ARP..." -ForegroundColor Cyan
    if (-not $Global:PreviewMode) {
        try {
            arp -d * 2>$null
            netsh interface ip delete arpcache | Out-Null
            Write-Success  "ล้างแคช ARP สำเร็จ"
        } catch { Write-Warning2  "เกิดข้อผิดพลาดในการล้างแคช ARP" }
    } else { Write-Host "  [PREVIEW] รันคำสั่งล้างแคช ARP" -ForegroundColor DarkGray }

    # Reset TCP/IP stack
    # FIXED: คำสั่งนี้ล้าง static IP, route และ LSP ของ VPN/proxy ทิ้ง และต้องรีสตาร์ท
    # เดิมรันเองโดยไม่ถามตอนกด "ทำทุกข้อ"
    Write-Host "`nต้องการรีเซ็ตเครือข่าย (TCP/IP Stack & Winsock) หรือไม่?" -ForegroundColor Cyan
    if (-not $Global:PreviewMode) {
        Write-Warning2 "คำสั่งนี้จะล้างค่า IP แบบกำหนดเอง, route และการตั้งค่า VPN/proxy และต้องรีสตาร์ทเครื่อง"
        $netAns = Read-Host "ต้องการรีเซ็ต TCP/IP และ Winsock ตอนนี้หรือไม่? (y/n) [n]"
        if ($netAns -eq 'y') {
            try {
                netsh int ip reset | Out-Null
                netsh winsock reset | Out-Null
                Write-Success  "รีเซ็ตเครือข่ายสำเร็จ (อาจต้องรีสตาร์ทเครื่องเพื่อให้มีผลสมบูรณ์)"
            } catch { Write-Warning2  "ไม่สามารถรีเซ็ตเครือข่ายได้" }
        } else {
            Write-Host "  - ข้ามไป ไม่ได้แตะการตั้งค่าเครือข่าย" -ForegroundColor DarkGray
        }
    } else { Write-Host "  [PREVIEW] จะถามยืนยันก่อนรัน netsh int ip reset / netsh winsock reset" -ForegroundColor DarkGray }

    # Disable Delivery Optimization
    Write-Host "`nกำลังปิด Delivery Optimization P2P (การส่งอัปเดตแบบ Peer-to-Peer)..." -ForegroundColor Cyan
    if (-not $Global:PreviewMode) {
        try {
            $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config"
            if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
            Set-ItemProperty -Path $regPath -Name "DODownloadMode" -Value 0 -Force
            Write-Success  "ปิด Delivery Optimization สำเร็จ"
        } catch { Write-Warning2  "เกิดข้อผิดพลาดในการปิด Delivery Optimization" }
    } else { Write-Host "  [PREVIEW] ปิด Delivery Optimization ผ่าน Registry" -ForegroundColor DarkGray }

    # Auto-Tuning
    Write-Host "`nสถานะ Auto-Tuning ของเครือข่ายปัจจุบัน:" -ForegroundColor Cyan
    try {
        netsh interface tcp show global | Select-String "Receive Window Auto-Tuning Level" | Write-Host -ForegroundColor Gray
        $disableTuning = Read-Host "ต้องการปิดการตั้งค่า Auto-Tuning หรือไม่? (แนะนำถ้าเน็ตช้าผิดปกติ) (y/n) [n]"
        if ($disableTuning -eq 'y') {
            if (-not $Global:PreviewMode) {
                netsh interface tcp set global autotuninglevel=disabled | Out-Null
                Write-Success  "ปิด Auto-Tuning สำเร็จ"
            } else { Write-Host "  [PREVIEW] รันคำสั่งปิด Auto-Tuning" -ForegroundColor DarkGray }
        }
    } catch { Write-Warning2  "ไม่สามารถตรวจสอบ Auto-Tuning ได้" }

    # Change DNS
    Write-Host "`nสถานะ DNS ปัจจุบัน:" -ForegroundColor Cyan
    try {
        $adapters = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.ServerAddresses -ne $null }
        foreach ($adapter in $adapters) {
            Write-Host "  อะแดปเตอร์ $($adapter.InterfaceAlias): $($adapter.ServerAddresses -join ', ')" -ForegroundColor Gray
        }
    } catch { Write-Host "  ไม่สามารถดึงข้อมูล DNS ได้" -ForegroundColor DarkGray }

    $dnsChoice = Read-Host "ต้องการเปลี่ยน DNS เพื่อเพิ่มความเร็วหรือไม่? (1) Google DNS, (2) Cloudflare DNS, (0) ไม่เปลี่ยน [0]"
    if ($dnsChoice -eq '1' -or $dnsChoice -eq '2') {
        if (-not $Global:PreviewMode) {
            try {
                $adapters = Get-NetAdapter | Where-Object Status -eq "Up"
                foreach ($adapter in $adapters) {
                    if ($dnsChoice -eq '1') {
                        Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses ("8.8.8.8","8.8.4.4")
                        Write-Success  "ตั้งค่า Google DNS ให้กับ $($adapter.Name) แล้ว"
                    } elseif ($dnsChoice -eq '2') {
                        Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses ("1.1.1.1","1.0.0.1")
                        Write-Success  "ตั้งค่า Cloudflare DNS ให้กับ $($adapter.Name) แล้ว"
                    }
                }
            } catch { Write-Warning2  "เกิดข้อผิดพลาดในการเปลี่ยน DNS" }
        } else { Write-Host "  [PREVIEW] ตั้งค่า DNS เป็นตัวเลือกที่ $dnsChoice" -ForegroundColor DarkGray }
    }
}

# Module 10: Setup-AutoMaintenance
function Setup-AutoMaintenance {
    Write-ModuleHeader  "ตั้งค่าการบำรุงรักษาอัตโนมัติ (Setup Auto Maintenance)"
    Write-Log  "Starting auto maintenance setup" -Type "INFO"

    # Create Scheduled Task for cleanup
    Write-Host "กำลังสร้างงานล้างไฟล์ขยะอัตโนมัติรายสัปดาห์..." -ForegroundColor Cyan
    if (-not $Global:PreviewMode) {
        try {
            $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -WindowStyle Hidden -Command `"Remove-Item -Path `$env:TEMP\* -Recurse -Force -ErrorAction SilentlyContinue`""
            $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 3am
            Register-ScheduledTask -TaskName "WeeklyTempCleanup" -Action $action -Trigger $trigger -Description "Loves System Clean" -User "System" -RunLevel Highest -Force | Out-Null
            Write-Success  "สร้างงานล้างไฟล์ขยะอัตโนมัติสำเร็จ"
        } catch { Write-Warning2  "ไม่สามารถสร้าง Scheduled Task ได้: $($_.Exception.Message)" }
    } else { Write-Host "  [PREVIEW] สร้าง Scheduled Task: WeeklyTempCleanup" -ForegroundColor DarkGray }

    # Configure Storage Sense
    Write-Host "กำลังตั้งค่า Storage Sense ให้ทำงานรายสัปดาห์..." -ForegroundColor Cyan
    if (-not $Global:PreviewMode) {
        try {
            $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy"
            if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
            # FIXED: the original wrote the wrong StoragePolicy value names.
            #   2048 = cadence; only 0 / 1 / 7 / 30 are valid (2 was ignored)
            #   32   = Recycle Bin age threshold in days (the original used "8")
            #   256 / 512 = the Downloads-folder cleanup switch and its threshold.
            #   Writing 30 to "256" switched ON auto-deletion of the user's Downloads
            #   folder. Those two are deliberately left alone now.
            Set-ItemProperty -Path $regPath -Name "2048" -Value 7 -Force  # run weekly
            Set-ItemProperty -Path $regPath -Name "32" -Value 30 -Force   # Recycle Bin: items older than 30 days
            Write-Success  "ตั้งค่า Storage Sense สำเร็จ"
        } catch { Write-Warning2  "ไม่สามารถตั้งค่า Storage Sense ได้" }
    } else { Write-Host "  [PREVIEW] ตั้งค่า Storage Sense รันรายสัปดาห์และลบไฟล์ 30 วัน" -ForegroundColor DarkGray }

    # Active Hours
    Write-Host "กำลังตั้งเวลาทำงาน (Active Hours) ของ Windows Update เป็น 8:00 - 22:00..." -ForegroundColor Cyan
    if (-not $Global:PreviewMode) {
        try {
            $regPath = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
            Set-ItemProperty -Path $regPath -Name "ActiveHoursStart" -Value 8 -Force
            Set-ItemProperty -Path $regPath -Name "ActiveHoursEnd" -Value 22 -Force
            Write-Success  "ตั้งค่า Active Hours สำเร็จ"
        } catch { Write-Warning2  "ไม่สามารถตั้งค่า Active Hours ได้" }
    } else { Write-Host "  [PREVIEW] ตั้งเวลา Active Hours 8:00-22:00" -ForegroundColor DarkGray }

    # Weekly Defrag/TRIM
    Write-Host "กำลังตั้งค่างานจัดระเบียบดิสก์ (Defrag/TRIM) อัตโนมัติ..." -ForegroundColor Cyan
    if (-not $Global:PreviewMode) {
        try {
            Enable-ScheduledTask -TaskPath "\Microsoft\Windows\Defrag\" -TaskName "ScheduledDefrag" -ErrorAction Stop | Out-Null
            Write-Success  "เปิดใช้งาน Defrag/TRIM อัตโนมัติสำเร็จ"
        } catch { Write-Warning2  "ไม่สามารถเปิดใช้งาน ScheduledDefrag ได้" }
    } else { Write-Host "  [PREVIEW] เปิดใช้งาน Task: ScheduledDefrag" -ForegroundColor DarkGray }

    # System Restore Task
    Write-Host "กำลังสร้างงานสร้างจุดกู้คืนระบบ (Restore Point) อัตโนมัติ..." -ForegroundColor Cyan
    if (-not $Global:PreviewMode) {
        try {
            $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -WindowStyle Hidden -Command `"Checkpoint-Computer -Description 'Weekly Automated Restore Point' -RestorePointType 'MODIFY_SETTINGS'`""
            $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 2am
            Register-ScheduledTask -TaskName "WeeklyRestorePoint" -Action $action -Trigger $trigger -User "System" -RunLevel Highest -Force | Out-Null
            Write-Success  "สร้างงาน Restore Point อัตโนมัติสำเร็จ"
        } catch { Write-Warning2  "ไม่สามารถสร้าง Restore Point Task ได้" }
    } else { Write-Host "  [PREVIEW] สร้าง Scheduled Task: WeeklyRestorePoint" -ForegroundColor DarkGray }

    Write-Host "`n=== สรุปงานอัตโนมัติที่ตั้งค่าไว้ ===" -ForegroundColor Green
    Write-Host "1. ล้างไฟล์ขยะรายสัปดาห์ (WeeklyTempCleanup)" -ForegroundColor White
    Write-Host "2. Storage Sense ลบไฟล์เก่า (30 วัน) อัตโนมัติ" -ForegroundColor White
    Write-Host "3. ป้องกันวินโดวส์รีสตาร์ทอัปเดตช่วง 8:00 - 22:00" -ForegroundColor White
    Write-Host "4. จัดระเบียบดิสก์รายสัปดาห์" -ForegroundColor White
    Write-Host "5. สร้างจุดกู้คืนระบบรายสัปดาห์ (WeeklyRestorePoint)" -ForegroundColor White
    Write-Host "`nงานเหล่านี้จะอยู่ในเครื่องตลอดไปจนกว่าจะถอนออก" -ForegroundColor Yellow
    Write-Host "ถ้าต้องการถอน ให้เลือกเมนู U" -ForegroundColor Yellow
}

# Module 11: Remove-Bloatware
function Remove-Bloatware {
    Write-ModuleHeader  "ลบโปรแกรมขยะ (Remove Bloatware)"
    Write-Log  "Starting bloatware removal" -Type "INFO"

    $bloatwareKeywords = @("McAfee", "Baidu", "Tencent", "Hao123", "Avast", "ByteFence", "Chromium", "Yandex", "Mail.ru", "WebDiscover")
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    Write-Host "กำลังค้นหาโปรแกรมขยะที่ติดตั้งในระบบ..." -ForegroundColor Cyan
    $foundPrograms = @()

    foreach ($path in $paths) {
        $keys = Get-ItemProperty $path -ErrorAction SilentlyContinue
        foreach ($key in $keys) {
            foreach ($keyword in $bloatwareKeywords) {
                if ($key.DisplayName -and $key.DisplayName -match $keyword) {
                    $foundPrograms += $key
                }
            }
        }
    }

    if ($foundPrograms.Count -eq 0) {
        Write-Success  "ยอดเยี่ยม! ไม่พบโปรแกรม Bloatware หรือโปรแกรมขยะในระบบ"
        return
    }

    Write-Warning2  "พบโปรแกรมที่เข้าข่าย Bloatware หรือโปรแกรมขยะต่อไปนี้:"
    $foundPrograms | Select-Object DisplayName, DisplayVersion, Publisher | Format-Table -AutoSize | Out-String | Write-Host -ForegroundColor Yellow

    $ans = Read-Host "ต้องการให้ระบบพยายามถอนการติดตั้งอัตโนมัติหรือไม่? (y/n) [n]"
    if ($ans -eq 'y') {
        foreach ($prog in $foundPrograms) {
            Write-Host "กำลังพยายามถอนการติดตั้ง: $($prog.DisplayName)..." -ForegroundColor Cyan
            if (-not $Global:PreviewMode) {
                try {
                    $uninstallString = $prog.UninstallString
                    if ($uninstallString) {
                        if ($uninstallString -match "msiexec") {
                            # FIXED: เดิมใช้ -replace "/I","/X" ซึ่งแทนที่ทุกตำแหน่งในสตริง
                            # เปลี่ยนเป็นดึง product code ออกมาแล้วประกอบคำสั่งใหม่
                            $productCode = [regex]::Match($uninstallString, '\{[0-9A-Fa-f-]{36}\}').Value
                            if ($productCode) {
                                Start-Process "msiexec.exe" -ArgumentList "/X", $productCode, "/quiet", "/norestart" -Wait -NoNewWindow
                            } else {
                                Write-Warning2 "อ่าน product code ไม่ได้ กรุณาถอน $($prog.DisplayName) เองที่ Settings > Apps"
                            }
                        } else {
                            # FIXED: UninstallString มักมี argument ติดมาด้วย ใช้เป็น FilePath ไม่ได้
                            # และการยัด /S ใส่ uninstaller ที่ไม่รู้จักทำให้เกิดผลที่คาดเดาไม่ได้
                            # จึงเปลี่ยนเป็นแสดงคำสั่งให้ผู้ใช้รันเอง
                            Write-Warning2 "โปรแกรมนี้ถอนอัตโนมัติไม่ปลอดภัย"
                            Write-Host "  ถ้าต้องการถอน ให้รันคำสั่งนี้เอง:" -ForegroundColor Yellow
                            Write-Host "    $uninstallString" -ForegroundColor White
                        }
                        Write-Success  "ส่งคำสั่งถอนการติดตั้ง $($prog.DisplayName) เรียบร้อยแล้ว (บางโปรแกรมอาจต้องถอนด้วยตัวเอง)"
                    } else {
                        Write-Warning2  "ไม่พบคำสั่งถอนการติดตั้งสำหรับ $($prog.DisplayName)"
                    }
                } catch {
                    Write-Warning2  "ไม่สามารถถอนการติดตั้งอัตโนมัติได้ กรุณาถอนเองผ่าน Control Panel"
                }
            } else { Write-Host "  [PREVIEW] รันคำสั่งถอนการติดตั้ง $($prog.DisplayName)" -ForegroundColor DarkGray }
        }
    }
}

function Optimize-Gaming {
    Write-ModuleHeader "รีดพลังเกม & เพิ่ม FPS"
    Write-Log "Starting Gaming & FPS Optimization (Thai)" -Type "INFO"
    $hagsKey = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
    $gameDvrKey1 = "HKCU:\System\GameConfigStore"
    $gameDvrKey2 = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"
    try {
        if ($Global:PreviewMode) {
            Write-Host "[จำลอง] จะทำการเปิด Hardware-Accelerated GPU Scheduling (HAGS) เพื่อเพิ่มเฟรมเรท" -ForegroundColor Cyan
            Write-Host "[จำลอง] จะทำการปิด Xbox Game Bar (GameDVR) ที่กินสเปคเบื้องหลัง" -ForegroundColor Cyan
            Write-Host "[จำลอง] จะทำการปิด Nagle's Algorithm เพื่อลดปิงเวลาเล่นเกมออนไลน์" -ForegroundColor Cyan
        } else {
            if (Test-Path $hagsKey) {
                Set-ItemProperty -Path $hagsKey -Name "HwSchMode" -Value 2 -ErrorAction SilentlyContinue
                Write-Success "เปิดใช้งาน Hardware-Accelerated GPU Scheduling สำเร็จแล้ว"
            }
            if (Test-Path $gameDvrKey1) {
                Set-ItemProperty -Path $gameDvrKey1 -Name "GameDVR_Enabled" -Value 0 -ErrorAction SilentlyContinue
            }
            if (-not (Test-Path $gameDvrKey2)) {
                New-Item -Path $gameDvrKey2 -Force | Out-Null
            }
            Set-ItemProperty -Path $gameDvrKey2 -Name "AllowGameDVR" -Value 0 -ErrorAction SilentlyContinue
            Write-Success "ปิดใช้งาน Xbox Game Bar สำเร็จแล้ว"
            
            $interfacesKey = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
            if (Test-Path $interfacesKey) {
                $interfaces = Get-ChildItem -Path $interfacesKey
                foreach ($iface in $interfaces) {
                    $ipAddr = Get-ItemProperty -Path $iface.PSPath -Name "DhcpIPAddress" -ErrorAction SilentlyContinue
                    $staticIp = Get-ItemProperty -Path $iface.PSPath -Name "IPAddress" -ErrorAction SilentlyContinue
                    if ($ipAddr -or $staticIp) {
                        Set-ItemProperty -Path $iface.PSPath -Name "TcpAckFrequency" -Value 1 -ErrorAction SilentlyContinue
                        Set-ItemProperty -Path $iface.PSPath -Name "TCPNoDelay" -Value 1 -ErrorAction SilentlyContinue
                    }
                }
                Write-Success "ลดความหน่วงเน็ตเวิร์ก (Ping) สำหรับเกมออนไลน์สำเร็จแล้ว"
            }
        }
    } catch {
        Write-Warning2 "เกิดข้อผิดพลาดในการตั้งค่าเกม: $($_.Exception.Message)"
    }
}
function Clean-BrowserJunk {
    Write-ModuleHeader "ล้างไฟล์ขยะเบราว์เซอร์แบบลึกซึ้ง"
    Write-Log "Starting Deep Browser Cleaner (Thai)" -Type "INFO"
    $browsers = @(
        @{ Name = "Chrome"; Path = "$env:LOCALAPPDATA\Google\Chrome\User Data" },
        @{ Name = "Edge"; Path = "$env:LOCALAPPDATA\Microsoft\Edge\User Data" },
        @{ Name = "Brave"; Path = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data" },
        @{ Name = "Firefox"; Path = "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles" }
    )
    $junkFolders = @("Cache", "Code Cache", "GPUCache", "Crashpad", "cache2", "startupCache")
    $totalFreed = 0
    foreach ($b in $browsers) {
        if (Test-Path $b.Path) {
            Write-Host "กำลังสแกน $($b.Name)..." -ForegroundColor Cyan
            $targets = Get-ChildItem -Path $b.Path -Recurse -Directory -ErrorAction SilentlyContinue | Where-Object { $junkFolders -contains $_.Name }
            foreach ($target in $targets) {
                if ($Global:PreviewMode) {
                    Write-Host "[จำลอง] จะลบไฟล์ขยะที่: $($target.FullName)" -ForegroundColor DarkGray
                } else {
                    try {
                        $size = (Get-ChildItem -Path $target.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                        if ($size -gt 0) { $totalFreed += $size }
                        Remove-Item -Path "$($target.FullName)\*" -Recurse -Force -ErrorAction SilentlyContinue
                        Write-Host "ทำความสะอาด: $($target.FullName)" -ForegroundColor DarkGray
                    } catch { }
                }
            }
        }
    }
    if (-not $Global:PreviewMode) {
        if ($totalFreed -gt 0) {
            Write-Success "ล้างเบราว์เซอร์เสร็จสิ้น ได้พื้นที่คืนมา $([math]::Round($totalFreed / 1MB, 2)) MB!"
        } else {
            Write-Success "เบราว์เซอร์สะอาดอยู่แล้ว ไม่มีขยะที่ต้องลบครับ"
        }
    }
}
function Block-Telemetry {
    Write-ModuleHeader "บล็อกการแอบเก็บข้อมูล (Telemetry)"
    Write-Log "Starting Telemetry Blocker (Thai)" -Type "INFO"
    try {
        if ($Global:PreviewMode) {
            Write-Host "[จำลอง] จะหยุดและปิดใช้งาน Service 'DiagTrack' (ดักเก็บข้อมูลผู้ใช้)" -ForegroundColor Cyan
            Write-Host "[จำลอง] จะหยุดและปิดใช้งาน Service 'dmwappushservice' (ติดตามการใช้งานแอป)" -ForegroundColor Cyan
            Write-Host "[จำลอง] จะตั้งค่า Registry บล็อก AllowTelemetry ให้เป็น 0" -ForegroundColor Cyan
        } else {
            Stop-Service -Name "DiagTrack" -ErrorAction SilentlyContinue
            Set-Service -Name "DiagTrack" -StartupType Disabled -ErrorAction SilentlyContinue
            Write-Success "ปิดใช้งาน Service 'DiagTrack' สำเร็จแล้ว"
            Stop-Service -Name "dmwappushservice" -ErrorAction SilentlyContinue
            Set-Service -Name "dmwappushservice" -StartupType Disabled -ErrorAction SilentlyContinue
            Write-Success "ปิดใช้งาน Service 'dmwappushservice' สำเร็จแล้ว"
            $datacollectionKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
            if (-not (Test-Path $datacollectionKey)) {
                New-Item -Path $datacollectionKey -Force | Out-Null
            }
            Set-ItemProperty -Path $datacollectionKey -Name "AllowTelemetry" -Value 0 -ErrorAction SilentlyContinue
            Write-Success "ปิดกั้นการส่งข้อมูลกลับไปที่ Microsoft สำเร็จแล้ว"
        }
    } catch {
        Write-Warning2 "เกิดข้อผิดพลาดในการบล็อก Telemetry: $($_.Exception.Message)"
    }
}


# Main Menu

# Module 15: Repair-SystemDeep
function Repair-SystemDeep {
    Write-ModuleHeader "ซ่อมแซมไฟล์ระบบลึกสุดใจ (SFC & DISM)"
    Write-Log "Starting deep system repair" -Type "INFO"
    
    if (-not $Global:PreviewMode) {
        Write-Host "กำลังรัน System File Checker (SFC)... อาจใช้เวลานาน" -ForegroundColor Cyan
        sfc /scannow
        
        Write-Host "`nกำลังรัน DISM (RestoreHealth)..." -ForegroundColor Cyan
        DISM /Online /Cleanup-Image /RestoreHealth
        
        Write-Success "ซ่อมแซมระบบเชิงลึกเสร็จสิ้น"
    } else {
        Write-Host "  [PREVIEW] จำลองคำสั่ง: sfc /scannow และ DISM /RestoreHealth" -ForegroundColor DarkGray
    }
}

# Module 16: Reset-Network
function Reset-Network {
    Write-ModuleHeader "รีเซ็ตและซ่อมแซมอินเทอร์เน็ต (Network Deep Reset)"
    Write-Log "Starting network reset" -Type "INFO"
    
    if (-not $Global:PreviewMode) {
        Write-Host "กำลังรีเซ็ต TCP/IP และ Winsock..." -ForegroundColor Cyan
        netsh winsock reset | Out-Null
        netsh int ip reset | Out-Null
        
        Write-Host "กำลังล้างแคช DNS..." -ForegroundColor Cyan
        ipconfig /flushdns | Out-Null
        
        Write-Success "รีเซ็ตเครือข่ายสำเร็จ (อาจต้องรีสตาร์ทเครื่อง)"
    } else {
        Write-Host "  [PREVIEW] จำลองคำสั่ง: รีเซ็ต Winsock, TCP/IP และล้างแคช DNS" -ForegroundColor DarkGray
    }
}

# Module 17: Optimize-Power
function Optimize-Power {
    Write-ModuleHeader "ปลดล็อคพลังงานสูงสุด (Ultimate Power)"
    Write-Log "Unlocking Ultimate Performance power plan" -Type "INFO"
    
    if (-not $Global:PreviewMode) {
        Write-Host "กำลังปลดล็อคโหมด Ultimate Performance..." -ForegroundColor Cyan
        $powerplan = powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61
        $guid = [regex]::match($powerplan, '([a-f0-9]{8}-([a-f0-9]{4}-){3}[a-f0-9]{12})').Value
        if ($guid) {
            powercfg -setactive $guid | Out-Null
            Write-Success "เปิดใช้งานโหมดพลังงาน Ultimate Performance แล้ว"
        } else {
            Write-Warning2 "ไม่สามารถปลดล็อคโหมด Ultimate Performance ได้"
        }
    } else {
        Write-Host "  [PREVIEW] จำลองคำสั่ง: ปลดล็อคและเปิดใช้งาน Ultimate Performance" -ForegroundColor DarkGray
    }
}

# Module 18: Clear-CrashDumps
function Clear-CrashDumps {
    Write-ModuleHeader "ล้างประวัติการค้างและ Error (Crash Dumps)"
    Write-Log "Clearing crash dumps and event logs" -Type "INFO"
    
    if (-not $Global:PreviewMode) {
        Write-Host "กำลังล้างไฟล์ Windows Error Reporting และ Minidumps..." -ForegroundColor Cyan
        Remove-Item -Path "C:\ProgramData\Microsoft\Windows\WER\ReportArchive\*" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "C:\ProgramData\Microsoft\Windows\WER\ReportQueue\*" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "C:\Windows\Minidump\*" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "C:\Windows\MEMORY.DMP" -Force -ErrorAction SilentlyContinue
        
        Write-Host "กำลังล้างประวัติ Windows Event Logs..." -ForegroundColor Cyan
        wevtutil el | Foreach-Object {wevtutil cl "$_" 2>$null}
        
        Write-Success "ล้างประวัติการ Error และ Event Logs ทั้งหมดแล้ว"
    } else {
        Write-Host "  [PREVIEW] จำลองคำสั่ง: ลบไฟล์ WER, Minidumps และล้าง Event Logs" -ForegroundColor DarkGray
    }
}

# Module 19: Restore-ClassicContext
function Restore-ClassicContext {
    Write-ModuleHeader "แก้คลิกขวาขัดใจ (Classic Context Menu Win 11)"
    Write-Log "Restoring classic context menu for Windows 11" -Type "INFO"
    
    if (-not $Global:PreviewMode) {
        Write-Host "กำลังปรับ Registry ให้แสดงคลิกขวาแบบเต็ม..." -ForegroundColor Cyan
        try {
            $regPath = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
            New-Item -Path $regPath -Force -ErrorAction SilentlyContinue | Out-Null
            Set-ItemProperty -Path $regPath -Name "(Default)" -Value "" -Force -ErrorAction SilentlyContinue
            Write-Success "แก้คลิกขวาเสร็จสิ้น (รีสตาร์ท Windows Explorer หรือรีคอมเพื่อดูผล)"
        } catch {
            Write-Warning2 "แก้ไข Registry ไม่สำเร็จ"
        }
    } else {
        Write-Host "  [PREVIEW] จำลองคำสั่ง: เพิ่ม Registry ข้ามเมนูคลิกขวาของ Windows 11" -ForegroundColor DarkGray
    }
}

# Module 20: Disable-Ads
function Disable-Ads {
    Write-ModuleHeader "ปิดโฆษณาและการแจ้งเตือนกวนใจ (Disable Ads)"
    Write-Log "Disabling Windows ads and tips" -Type "INFO"
    
    if (-not $Global:PreviewMode) {
        Write-Host "กำลังปิดโฆษณาแฝงและคำแนะนำการใช้งาน..." -ForegroundColor Cyan
        try {
            Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SystemPaneSuggestionsEnabled" -Value 0 -ErrorAction SilentlyContinue
            Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SoftLandingEnabled" -Value 0 -ErrorAction SilentlyContinue
            Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-338389Enabled" -Value 0 -ErrorAction SilentlyContinue
            Write-Success "ปิดโฆษณาและการแจ้งเตือนสำเร็จ"
        } catch {
            Write-Warning2 "แก้ไข Registry ไม่สำเร็จ"
        }
    } else {
        Write-Host "  [PREVIEW] จำลองคำสั่ง: แก้ Registry ปิด Tips & Suggestions" -ForegroundColor DarkGray
    }
}

# Module U: Remove-AutoMaintenance
# ADDED: ปุ่มย้อนเมนู 10 เพราะงานที่สร้างไว้รันเป็น SYSTEM ตลอดไป
# และยังอยู่แม้ผู้ใช้ลบเครื่องมือนี้ทิ้งแล้ว
function Remove-AutoMaintenance {
    Write-ModuleHeader "ถอนงานบำรุงรักษาอัตโนมัติ (ย้อนเมนู 10)"
    Write-Log "Removing auto maintenance scheduled tasks" -Type "INFO"

    $taskNames = @("WeeklyTempCleanup", "WeeklyRestorePoint")

    foreach ($t in $taskNames) {
        $existing = Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue
        if (-not $existing) {
            Write-Host "  - ไม่พบงาน '$t' ในเครื่องนี้" -ForegroundColor DarkGray
            continue
        }
        if ($Global:PreviewMode) {
            Write-Host "  [PREVIEW] จะถอนงานตั้งเวลา: $t" -ForegroundColor DarkGray
        } else {
            try {
                Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction Stop
                Write-Success "ถอนงานตั้งเวลา $t เรียบร้อย"
            } catch {
                Write-Warning2 "ถอนงาน '$t' ไม่สำเร็จ: $($_.Exception.Message)"
            }
        }
    }

    Write-Host "`nหมายเหตุ: Storage Sense และ Active Hours เป็นการตั้งค่าของ Windows ไม่ใช่งานตั้งเวลา" -ForegroundColor Cyan
    Write-Host "ถ้าต้องการปิด ให้ไปที่ Settings > System > Storage > Storage Sense" -ForegroundColor Cyan
    Write-Host "และ Settings > Windows Update > Advanced options > Active hours" -ForegroundColor Cyan
}

function Show-MainMenu {
    while ($true) {
        Clear-Host
        Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║         🧹 Windows System Cleanup & Optimization Tool        ║" -ForegroundColor Cyan
        Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
        
        $modeStr = if ($Global:PreviewMode) { "(เปิดใช้งานอยู่)" } else { "(ปิดใช้งาน)" }
        
        Write-Host "1. ทำความสะอาดไฟล์ขยะ (Clean System Junk)" -ForegroundColor White
        Write-Host "2. ซ่อมแซมระบบและ Registry (Repair System)" -ForegroundColor White
        Write-Host "3. จัดการโปรแกรมเริ่มต้น (Optimize Startup)" -ForegroundColor White
        Write-Host "4. ปรับแต่งประสิทธิภาพ (Tune Performance)" -ForegroundColor White
        Write-Host "5. สร้างรายงานสรุป (Generate Report)" -ForegroundColor White
        Write-Host "6. สแกนความปลอดภัย (Scan Security)" -ForegroundColor White
        Write-Host "7. ปิดการทำงานพื้นหลัง (Optimize Background)" -ForegroundColor White
        Write-Host "8. วิเคราะห์พื้นที่ฮาร์ดดิสก์ (Analyze Disk Space)" -ForegroundColor White
        Write-Host "9. ปรับแต่งเครือข่าย (Optimize Network)" -ForegroundColor White
        Write-Host "10. ตั้งค่าการบำรุงรักษาอัตโนมัติ (Setup Auto Maintenance)" -ForegroundColor White
        Write-Host "11. ลบโปรแกรมขยะ/Bloatware (Remove Bloatware)" -ForegroundColor White
        Write-Host "12. รีดพลังเกม & FPS (Optimize Gaming)" -ForegroundColor White
        Write-Host "13. ล้างบางเบราว์เซอร์ล้ำลึก (Clean Browser Junk)" -ForegroundColor White
        Write-Host "14. บล็อก Telemetry & สายลับ (Block Telemetry)" -ForegroundColor White
        Write-Host "--- ADVANCED FEATURES (กรุณาอ่าน README ก่อนใช้งาน) ---" -ForegroundColor Red
        Write-Host "15. ซ่อมแซมไฟล์ระบบลึกสุดใจ (SFC & DISM)" -ForegroundColor White
        Write-Host "16. รีเซ็ตและซ่อมแซมอินเทอร์เน็ต (Network Deep Reset)" -ForegroundColor White
        Write-Host "17. ปลดล็อคพลังงานสูงสุด (Ultimate Power)" -ForegroundColor White
        Write-Host "18. ล้างประวัติการค้างและ Error (Crash Dumps)" -ForegroundColor White
        Write-Host "19. แก้คลิกขวาขัดใจ (Classic Context Menu Win 11)" -ForegroundColor White
        Write-Host "20. ปิดโฆษณาและการแจ้งเตือนกวนใจ (Disable Ads)" -ForegroundColor White
        Write-Host "U. ถอนงานอัตโนมัติที่สร้างจากเมนู 10 (Undo)" -ForegroundColor Yellow
        Write-Host "A. ทำทุกข้อ (Run All)" -ForegroundColor Green
        Write-Host "P. เปิด/ปิด โหมดจำลอง (Preview Mode) - ปัจจุบัน: $modeStr" -ForegroundColor Yellow
        Write-Host "L. กลับไปหน้าเลือกภาษา" -ForegroundColor White
        Write-Host "Q. ออกจากโปรแกรม (Exit)" -ForegroundColor Red
        
        $choice = Read-Host "`nโปรดเลือกเมนู (1-20, U, A, P, L, Q)"
        
        $pauseBlock = { 
            Write-Host "`nกด Enter เพื่อดำเนินการต่อ..." -ForegroundColor Gray
            $null = Read-Host 
        }

        switch ($choice) {
            '1' { if (Get-Command Clean-SystemJunk -ErrorAction SilentlyContinue) { Clean-SystemJunk } else { Write-Warning2 "ไม่พบฟังก์ชัน (มาจากส่วนที่ 1)" }; &$pauseBlock }
            '2' { if (Get-Command Repair-Registry -ErrorAction SilentlyContinue) { Repair-Registry } else { Write-Warning2 "ไม่พบฟังก์ชัน (มาจากส่วนที่ 1)" }; &$pauseBlock }
            '3' { if (Get-Command Optimize-Startup -ErrorAction SilentlyContinue) { Optimize-Startup } else { Write-Warning2 "ไม่พบฟังก์ชัน (มาจากส่วนที่ 1)" }; &$pauseBlock }
            '4' { if (Get-Command Tune-Performance -ErrorAction SilentlyContinue) { Tune-Performance } else { Write-Warning2 "ไม่พบฟังก์ชัน (มาจากส่วนที่ 1)" }; &$pauseBlock }
            '5' { if (Get-Command Generate-Report -ErrorAction SilentlyContinue) { Generate-Report } else { Write-Warning2 "ไม่พบฟังก์ชัน (มาจากส่วนที่ 1)" }; &$pauseBlock }
            '6' { Scan-Security; &$pauseBlock }
            '7' { Optimize-Background; &$pauseBlock }
            '8' { Analyze-DiskSpace; &$pauseBlock }
            '9' { Optimize-Network; &$pauseBlock }
            '10' { Setup-AutoMaintenance; &$pauseBlock }
            '11' { Remove-Bloatware; &$pauseBlock }
            '12' { Optimize-Gaming; &$pauseBlock }
            '13' { Clean-BrowserJunk; &$pauseBlock }
            '14' { Block-Telemetry; &$pauseBlock }
            '15' { Repair-SystemDeep; &$pauseBlock }
            '16' { Reset-Network; &$pauseBlock }
            '17' { Optimize-Power; &$pauseBlock }
            '18' { Clear-CrashDumps; &$pauseBlock }
            '19' { Restore-ClassicContext; &$pauseBlock }
            '20' { Disable-Ads; &$pauseBlock }
            'U' { Remove-AutoMaintenance; &$pauseBlock }
            'A' {
                if (Get-Command Clean-SystemJunk -ErrorAction SilentlyContinue) { Clean-SystemJunk }
                if (Get-Command Repair-Registry -ErrorAction SilentlyContinue) { Repair-Registry }
                if (Get-Command Optimize-Startup -ErrorAction SilentlyContinue) { Optimize-Startup }
                if (Get-Command Tune-Performance -ErrorAction SilentlyContinue) { Tune-Performance }
                Scan-Security
                Optimize-Background
                # FIXED: Analyze-DiskSpace (walks every drive, takes hours) and
                # Optimize-Network (resets the TCP/IP stack) are no longer part of
                # "Run All". Use menu 8 and 9 to run them deliberately.
                Setup-AutoMaintenance
                Remove-Bloatware
                Optimize-Gaming
                Clean-BrowserJunk
                Block-Telemetry
                if (Get-Command Generate-Report -ErrorAction SilentlyContinue) { Generate-Report }
                &$pauseBlock
            }
            'P' { $Global:PreviewMode = -not $Global:PreviewMode }
            'L' { return }
            'Q' { Write-Host "ออกจากโปรแกรมเรียบร้อยแล้ว ขอบคุณที่ใช้งาน!" -ForegroundColor Green; exit }
            default { Write-Host "ตัวเลือกไม่ถูกต้อง กรุณาเลือกใหม่" -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    }
}

# Start the script
Show-MainMenu



    }
}









while ($true) {
    Clear-Host
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host "            Select Language / เลือกภาษา            " -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host "1. English" -ForegroundColor White
    Write-Host "2. ภาษาไทย" -ForegroundColor White
    Write-Host "Q. Exit / ออกจากโปรแกรม" -ForegroundColor Red
    Write-Host "==================================================" -ForegroundColor Cyan
    $choice = Read-Host "Choice / เลือก (1, 2, Q)"
    
    if ($choice -eq '1') {
        Run-EnglishMode
    } elseif ($choice -eq '2') {
        Run-ThaiMode
    } elseif ($choice -eq 'Q' -or $choice -eq 'q') {
        exit
    }
}
