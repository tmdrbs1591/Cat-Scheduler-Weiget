# Removes the CAT schedule widget for the current user.
$Dest = Join-Path $env:LOCALAPPDATA 'CatScheduleWidget'
$ps1 = Join-Path $Dest 'wallpaper.ps1'
if (Test-Path $ps1) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $ps1 -Stop
    & powershell -NoProfile -ExecutionPolicy Bypass -File $ps1 -Uninstall | Out-Null
}
Remove-Item (Join-Path ([Environment]::GetFolderPath('Desktop')) 'CAT Schedule Widget.lnk') -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Remove-Item $Dest -Recurse -Force -ErrorAction SilentlyContinue
Write-Host 'Removed.'
