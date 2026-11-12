# Collects what is needed to look into a widget problem, saves it to the desktop and copies it to the clipboard.
# Login information is not included. The Windows user name in paths is masked.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$dirs = @((Join-Path $env:LOCALAPPDATA 'CatScheduleWidget'), $here, (Join-Path $here 'app'))   # installed copy first | Select-Object -Unique
$dir  = $dirs | Where-Object { Test-Path (Join-Path $_ 'wallpaper.ps1') } | Select-Object -First 1
if (-not $dir) { $dir = $here }
$log  = Join-Path $dir 'wallpaper.log'
$out  = New-Object System.Collections.Generic.List[string]
function Add($s) { $out.Add([string]$s) }
function Try-Get([scriptblock]$b) { try { & $b } catch { "(확인 실패: $($_.Exception.Message))" } }

Add "===== CAT 일정 위젯 문제 보고 ====="
Add "작성 시각   : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Add "설치 위치   : $dir"
$ver = try { (Get-Content (Join-Path $dir 'version.txt') -TotalCount 1 -ErrorAction Stop).Trim() } catch { '이전 버전 (version.txt 없음)' }
Add "버전        : $ver"
Add "Windows     : $(Try-Get { $o = Get-CimInstance Win32_OperatingSystem; "$($o.Caption) $($o.Version)" })"
Add "PowerShell  : $($PSVersionTable.PSVersion) / 언어모드 $($ExecutionContext.SessionState.LanguageMode) / 실행정책 $(Try-Get { Get-ExecutionPolicy })"
$edge = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
if (-not (Test-Path $edge)) { $edge = "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe" }
Add "Edge        : $(if (Test-Path $edge) { "$((Get-Item $edge).VersionInfo.ProductVersion)  ($edge)" } else { '찾을 수 없음' })"
Add "화면        : $(Try-Get { Add-Type -AssemblyName System.Windows.Forms; ([System.Windows.Forms.Screen]::AllScreens | ForEach-Object { "$($_.Bounds.Width)x$($_.Bounds.Height)$(if ($_.Primary) {'(주)'})" }) -join ', ' })"
Add "실행 중     : $(Try-Get {
    $ps = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like '*wallpaper.ps1*' }).Count
    $ed = @(Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" | Where-Object { $_.CommandLine -like "*$dir*" }).Count
    "위젯 스크립트 $ps 개, 위젯 Edge 프로세스 $ed 개" })"
Add "위젯 서버   : $(try { $r = Invoke-WebRequest 'http://localhost:39217/' -UseBasicParsing -TimeoutSec 3; "응답함 ($($r.StatusCode))" } catch { "응답 없음 ($($_.Exception.Message))" })"
Add "자동 실행   : $(if (Test-Path (Join-Path ([Environment]::GetFolderPath('Startup')) 'CalendarWallpaper.lnk')) { '등록됨' } else { '등록 안 됨' })"
Add "로그인 정보 : $(if (Test-Path (Join-Path $dir 'edge-profile')) { '프로필 폴더 있음' } else { '프로필 폴더 없음 (아직 실행 전?)' })"
Add ""
Add "===== 최근 로그 (wallpaper.log, 마지막 200줄) ====="
if (Test-Path $log) { Get-Content $log -Tail 200 -Encoding UTF8 | ForEach-Object { Add $_ } } else { Add "(로그 파일 없음: $log)" }

$text = ($out -join "`r`n") -replace [regex]::Escape($env:USERNAME), '<user>'
$file = Join-Path ([Environment]::GetFolderPath('Desktop')) 'CAT위젯_문제보고.txt'
Set-Content $file $text -Encoding UTF8
try { Set-Clipboard -Value $text } catch {}
Start-Process notepad.exe $file
Write-Host "Saved to desktop: CAT위젯_문제보고.txt (also copied to clipboard)"
