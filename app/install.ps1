# Installs the CAT schedule widget for the current user.
param([string]$Dest = (Join-Path $env:LOCALAPPDATA 'CatScheduleWidget'), [switch]$NoStartup, [switch]$NoLaunch)
$ErrorActionPreference = 'Stop'
$src = Split-Path -Parent $MyInvocation.MyCommand.Path
$ps1 = Join-Path $Dest 'wallpaper.ps1'

# stop a running copy before updating (login data in edge-profile is kept)
if (Test-Path $ps1) { & powershell -NoProfile -ExecutionPolicy Bypass -File $ps1 -Stop; Start-Sleep -Milliseconds 800 }

New-Item -ItemType Directory -Force $Dest | Out-Null
Get-ChildItem $src -Exclude 'install.ps1' | Copy-Item -Destination $Dest -Recurse -Force
Get-ChildItem $Dest -Recurse -File | Unblock-File

# desktop shortcut to (re)open the widget
$lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'CAT Schedule Widget.lnk'
$sc = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
$sc.TargetPath = 'powershell.exe'
$sc.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ps1`""
$sc.WindowStyle = 7
$sc.IconLocation = "$(Join-Path $Dest 'cat.ico'),0"
$sc.Save()

if (-not $NoStartup) { & powershell -NoProfile -ExecutionPolicy Bypass -File $ps1 -Install | Out-Null }
if (-not $NoLaunch) { Start-Process powershell -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$ps1`"" }
Write-Host "Installed to $Dest"
