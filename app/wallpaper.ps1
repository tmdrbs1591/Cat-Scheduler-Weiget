# Desktop widget: shows a web page in a small window that sits on the desktop
# (always just above the wallpaper, below other windows, survives Win+D, no taskbar button).
# The window is fully usable: click, scroll, move, resize. Position/size are remembered.
#
#   wallpaper.ps1             -> start widget
#   wallpaper.ps1 -Stop       -> close widget
#   wallpaper.ps1 -Install    -> run at Windows startup
#   wallpaper.ps1 -Uninstall  -> remove from startup
param(
    [switch]$Stop,
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$Login,  # kept for compatibility: opens a normal window
    [int]$DebugPort = 0   # testing only
)

$WindowName = 'Cat Scheduler Widget'
$Repo       = 'tmdrbs1591/Cat-Scheduler-Weiget'
$Project    = 'CAT'
$SiteUrl    = "https://loadcomplete-scheduler.web.app/?project=$Project"
$Port       = 39217
$Url        = "http://localhost:$Port/?project=$Project"
$Here       = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProfileDir = Join-Path $Here 'edge-profile'
$StateFile  = Join-Path $Here 'widget-pos.json'
$WidgetDir  = Join-Path $Here 'widget'
$LogFile    = Join-Path $Here 'wallpaper.log'
$AppVersion = try { (Get-Content (Join-Path $Here 'version.txt') -TotalCount 1).Trim() } catch { '0.0' }
if (-not $AppVersion) { $AppVersion = '0.0' }
$Edge       = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
if (-not (Test-Path $Edge)) { $Edge = "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe" }

function Log($m) {
    try { "$(Get-Date -Format 'MM-dd HH:mm:ss') $m" | Add-Content $LogFile -Encoding UTF8 } catch {}
}
# keep the log small: when it passes ~300 KB keep the newest 1500 lines
function Trim-Log {
    try { if ((Test-Path $LogFile) -and (Get-Item $LogFile).Length -gt 300KB) {
        $keep = Get-Content $LogFile -Tail 1500 -Encoding UTF8; Set-Content $LogFile $keep -Encoding UTF8 } } catch {}
}

function Get-OurEdge {
    Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" |
        Where-Object { $_.CommandLine -and $_.CommandLine.Contains($ProfileDir) }
}
function Stop-OurEdge {
    # previous widget instances (their loop holds the local port)
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
        Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -and $_.CommandLine.Contains('wallpaper.ps1') -and -not $_.CommandLine.Contains('-Install') } |
        ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop } catch {} }
    Get-OurEdge | ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop } catch {} }
    # widget windows of any other copy (they all use the same local port, only one can work)
    Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" |
        Where-Object { $_.CommandLine -and $_.CommandLine.Contains("--app=http://localhost:$Port/") } |
        ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop } catch {} }
}

if ($Stop) { Stop-OurEdge; return }

# ---------- auto update from GitHub (skipped in a dev copy that has a .dev file) ----------
function Update-Available {
    if (Test-Path (Join-Path $Here '.dev')) { return $null }
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $u = "https://raw.githubusercontent.com/$Repo/main/app/version.txt?nocache=$(Get-Random)"
        $remote = (Invoke-WebRequest $u -UseBasicParsing -TimeoutSec 8 -Headers @{ 'Cache-Control' = 'no-cache' }).Content.Trim()
        if ([version]$remote -gt [version]$AppVersion) { return $remote }
    } catch { Log "update check failed: $($_.Exception.Message)" }
    return $null
}
function Install-Update([string]$remote) {
    $tmp = Join-Path $env:TEMP ("catwidget-update-" + [guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Force $tmp | Out-Null
        $zip = Join-Path $tmp 'u.zip'
        Invoke-WebRequest "https://github.com/$Repo/archive/refs/heads/main.zip" -UseBasicParsing -OutFile $zip -TimeoutSec 60
        Expand-Archive $zip -DestinationPath $tmp -Force
        $src = Get-ChildItem $tmp -Directory | ForEach-Object { Join-Path $_.FullName 'app' } | Where-Object { Test-Path (Join-Path $_ 'wallpaper.ps1') } | Select-Object -First 1
        if (-not $src) { throw 'app folder not found in download' }
        $got = (Get-Content (Join-Path $src 'version.txt') -TotalCount 1).Trim()
        if ($got -ne $remote) { throw "downloaded version $got, expected $remote (GitHub still updating?)" }
        Get-ChildItem $src | Copy-Item -Destination $Here -Recurse -Force      # edge-profile / settings are not in the repo, so they stay
        Get-ChildItem $Here -Recurse -File -Exclude 'edge-profile' | Where-Object { $_.FullName -notlike '*\edge-profile\*' } | Unblock-File -ErrorAction SilentlyContinue
        Log "updated $AppVersion -> $remote"
        return $true
    } catch { Log "update failed: $($_.Exception.Message)"; return $false }
    finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
function Restart-Self {
    $vbs = Join-Path $Here 'launch.vbs'
    if (Test-Path $vbs) { Start-Process wscript.exe -ArgumentList "`"$vbs`"" }
    else { Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$(Join-Path $Here 'wallpaper.ps1')`"" }
}

trap {
    Log ("FATAL: " + ($_ | Out-String).Trim() + " | at " + $_.InvocationInfo.PositionMessage.Trim() + " | stack: " + $_.ScriptStackTrace)
    break
}

$Lnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'CalendarWallpaper.lnk'
if ($Install) {
    $sc = (New-Object -ComObject WScript.Shell).CreateShortcut($Lnk)
    $sc.TargetPath = 'wscript.exe'
    $sc.Arguments = "`"$(Join-Path $Here 'launch.vbs')`""
    $sc.WindowStyle = 7
    $ico = Join-Path $Here 'cat.ico'; if (Test-Path $ico) { $sc.IconLocation = "$ico,0" }
    $sc.Save()
    Write-Host "Registered to run at startup: $Lnk"
    return
}
if ($Uninstall) { Remove-Item $Lnk -ErrorAction SilentlyContinue; Write-Host 'Removed from startup.'; return }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class W {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string n);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
    [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr h, int i, int v);
    [DllImport("user32.dll")] public static extern IntPtr SetWindowLongPtr(IntPtr h, int i, IntPtr v);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint f);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern bool SetWindowText(IntPtr h, string s);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    public static string Title(IntPtr h) { var sb = new StringBuilder(128); GetWindowText(h, sb, 128); return sb.ToString(); }
    [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint cmd);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern int SetWindowRgn(IntPtr h, IntPtr rgn, bool redraw);
    [DllImport("gdi32.dll")] public static extern IntPtr CreateRoundRectRgn(int x1, int y1, int x2, int y2, int w, int h);
    [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int attr, out RECT r, int size);
    [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
    [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int v, int size);
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vk);

    public static IntPtr FindTopWindowOf(uint[] pids) {
        IntPtr found = IntPtr.Zero;
        IntPtr progman = FindWindow("Progman", null);
        EnumWindows((h, l) => {
            uint pid; GetWindowThreadProcessId(h, out pid);
            if (Array.IndexOf(pids, pid) < 0 || !IsWindowVisible(h)) return true;
            var sb = new StringBuilder(256); GetClassName(h, sb, 256);
            if (sb.ToString() != "Chrome_WidgetWin_1") return true;
            RECT r; GetWindowRect(h, out r);
            if (r.R - r.L < 200 || r.B - r.T < 150) return true;   // skip bubbles/popups
            IntPtr owner = GetWindow(h, 4);
            // our widget is owned by Progman; anything else that is owned is a popup
            if (owner != IntPtr.Zero && owner != progman) return true;
            found = h; return false;
        }, IntPtr.Zero);
        return found;
    }
}
'@
[W]::SetProcessDPIAware() | Out-Null
Trim-Log
Log "===== start v$AppVersion ====="
try {
    $os = Get-CimInstance Win32_OperatingSystem
    $edgeVer = if (Test-Path $Edge) { (Get-Item $Edge).VersionInfo.ProductVersion } else { 'NOT FOUND' }
    $scr = ([System.Windows.Forms.Screen]::AllScreens | ForEach-Object { "$($_.Bounds.Width)x$($_.Bounds.Height)$(if ($_.Primary) {'*'})" }) -join ','
    Log "env: $($os.Caption) $($os.Version) | PS $($PSVersionTable.PSVersion) | Edge $edgeVer | screens $scr | dir $Here"
} catch { Log "env: (failed: $_)" }
if (-not (Test-Path $Edge)) { Log 'ERROR: Microsoft Edge not found'; exit 1 }
$newVer = Update-Available
if ($newVer -and (Install-Update $newVer)) { Restart-Self; exit 0 }

# Restore last position/size, or default to the top-right of the primary screen
$wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$state = $null
if (Test-Path $StateFile) { try { $state = Get-Content $StateFile -Raw | ConvertFrom-Json } catch {} }
if (-not $state) {
    $state = [pscustomobject]@{ X = $wa.Right - 480 - 24; Y = $wa.Top + 24; W = 480; H = 700 }
}

Stop-OurEdge
Start-Sleep -Milliseconds 800

# Tiny local web server for the widget page (Firebase allows sign-in from localhost)
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$ok = $false
for ($t = 0; $t -lt 20 -and -not $ok; $t++) {      # previous instance may still be releasing the port
    try { $listener.Start(); $ok = $true } catch { Start-Sleep -Milliseconds 500
        $listener = New-Object System.Net.HttpListener; $listener.Prefixes.Add("http://localhost:$Port/") }
}
if (-not $ok) { Log "ERROR: port $Port busy (another program uses it?)"; exit 1 }
$pending = $listener.GetContextAsync()

function Set-Frameless($h, [bool]$on) {
    # No clipping: the window keeps its normal edges so it can always be resized.
    # Windows 11 rounds the corners for us.
    if ($h -eq [IntPtr]::Zero) { return }
    [W]::SetWindowRgn($h, [IntPtr]::Zero, $true) | Out-Null
    $round = 2
    [W]::DwmSetWindowAttribute($h, 33, [ref]$round, 4) | Out-Null   # DWMWA_WINDOW_CORNER_PREFERENCE = ROUND
}

function Handle-Request($ctx) {
    $path = $ctx.Request.Url.AbsolutePath
    $res = $ctx.Response
    $body = $null; $type = 'text/plain; charset=utf-8'; $doDrag = $false
    switch -Regex ($path) {
        '^/$|^/index\.html$' {
            # icon URL carries the version so Edge never keeps showing an old cached taskbar icon
            $html = [IO.File]::ReadAllText((Join-Path $WidgetDir 'index.html'), [Text.Encoding]::UTF8).Replace('/icons/cat.png"', "/icons/cat.png?v=$AppVersion`"")
            $body = [Text.Encoding]::UTF8.GetBytes($html); $type = 'text/html; charset=utf-8' }
        '^/cmd/edit$' { $script:editing = $true;  Set-Frameless $script:hwnd $false
                        [W]::SetWindowPos($script:hwnd, [IntPtr]0, 0, 0, 0, 0, 0x1 -bor 0x2) | Out-Null; $body = [Text.Encoding]::UTF8.GetBytes('ok') }
        '^/cmd/done$' { $script:editing = $false; Set-Frameless $script:hwnd $true; $body = [Text.Encoding]::UTF8.GetBytes('ok') }
        '^/icons/[a-z0-9_-]+\.png$' {
            $f = Join-Path (Join-Path $WidgetDir 'icons') ([IO.Path]::GetFileName($path))
            if (Test-Path $f) { $body = [IO.File]::ReadAllBytes($f); $type = 'image/png' }
            else { $res.StatusCode = 404; $body = [Text.Encoding]::UTF8.GetBytes('not found') } }
        '^/cmd/resize$' {
            # grow/shrink the window height by dh CSS pixels (top edge stays put)
            $dh = 0; [int]::TryParse($ctx.Request.QueryString['dh'], [ref]$dh) | Out-Null
            $h = $script:hwnd
            if ($h -ne [IntPtr]::Zero -and $dh -ne 0) {
                $scale = [W]::GetDpiForWindow($h) / 96.0
                $r = New-Object W+RECT; [W]::GetWindowRect($h, [ref]$r) | Out-Null
                $newH = [Math]::Max(160, ($r.B - $r.T) + [int][Math]::Round($dh * $scale))
                [W]::SetWindowPos($h, [IntPtr]::Zero, 0, 0, $r.R - $r.L, $newH, 0x2 -bor 0x4 -bor 0x10) | Out-Null
            }
            $body = [Text.Encoding]::UTF8.GetBytes('ok') }
        '^/log$' {
            try { $txt = (New-Object IO.StreamReader($ctx.Request.InputStream, [Text.Encoding]::UTF8)).ReadToEnd() } catch { $txt = '' }
            if ($txt.Length -gt 1500) { $txt = $txt.Substring(0, 1500) + '...' }
            Log ("[page] " + ($txt -replace "[`r`n]+", ' '))
            $body = [Text.Encoding]::UTF8.GetBytes('ok') }
        '^/update/status$' { $type = 'application/json'
            $body = [Text.Encoding]::UTF8.GetBytes((@{ current = $AppVersion; available = "$($script:updateReady)" } | ConvertTo-Json -Compress)) }
        '^/update/now$' { $script:trayCmd = 'updatenow'; $body = [Text.Encoding]::UTF8.GetBytes('ok') }
        '^/cmd/drag$' { $doDrag = $true; $body = [Text.Encoding]::UTF8.GetBytes('ok') }
        '^/cmd/site$' { Start-Process $SiteUrl; $body = [Text.Encoding]::UTF8.GetBytes('ok') }
        default       { $res.StatusCode = 404; $body = [Text.Encoding]::UTF8.GetBytes('not found') }
    }
    $res.ContentType = $type
    $res.Headers.Add('Cache-Control', 'no-store')
    $res.OutputStream.Write($body, 0, $body.Length)
    $res.Close()
    if ($doDrag) { Drag-Window $script:hwnd }
}

# Move the window with the mouse until the left button is released
function Drag-Window($h) {
    if ($h -eq [IntPtr]::Zero) { return }
    $p = New-Object W+POINT; $r = New-Object W+RECT
    [W]::GetCursorPos([ref]$p) | Out-Null
    [W]::GetWindowRect($h, [ref]$r) | Out-Null
    $dx = $p.X - $r.L; $dy = $p.Y - $r.T
    $lastX = $null; $lastY = $null
    while ([W]::GetAsyncKeyState(0x01) -band 0x8000) {
        [W]::GetCursorPos([ref]$p) | Out-Null
        $nx = $p.X - $dx; $ny = $p.Y - $dy
        if ($nx -ne $lastX -or $ny -ne $lastY) {
            [W]::SetWindowPos($h, [IntPtr]::Zero, $nx, $ny, 0, 0, 0x1 -bor 0x4 -bor 0x10) | Out-Null   # NOSIZE|NOZORDER|NOACTIVATE
            $lastX = $nx; $lastY = $ny
        }
        Start-Sleep -Milliseconds 10
    }
}

function Pump-Requests([int]$ms) {
    if ($script:pending.Wait($ms)) {
        try { Handle-Request $script:pending.Result } catch { Log "request error: $_" }
        $script:pending = $listener.GetContextAsync()
    }
}
$editing = $false
$hwnd = [IntPtr]::Zero

$edgeArgs = @(
    "--app=$Url",
    "--user-data-dir=`"$ProfileDir`"",
    '--no-first-run',
    '--no-default-browser-check',
    '--disable-features=Translate,msEdgeTranslate',
    '--disable-translate',
    "--window-position=$($state.X),$($state.Y)",
    "--window-size=$($state.W),$($state.H)"
)
if ($DebugPort -gt 0) { $edgeArgs += "--remote-debugging-port=$DebugPort" }
if ($Login) { Start-Process $Edge -ArgumentList $edgeArgs; return }
Start-Process $Edge -ArgumentList $edgeArgs

function Find-Widget {
    $pids = [uint32[]]@(Get-OurEdge | ForEach-Object { [uint32]$_.ProcessId })
    if ($pids.Count -eq 0) { return [IntPtr]::Zero }
    return [W]::FindTopWindowOf($pids)
}

# Wait until Edge's main window exists and is stable (Edge may replace its first window)
$hwnd = [IntPtr]::Zero; $stable = 0
for ($i = 0; $i -lt 60 -and $stable -lt 3; $i++) {
    Pump-Requests 350; Pump-Requests 350
    $h2 = Find-Widget
    if ($h2 -ne [IntPtr]::Zero -and $h2 -eq $hwnd) { $stable++ } else { $stable = 0; $hwnd = $h2 }
}
if ($hwnd -eq [IntPtr]::Zero) {
    $n = (Get-OurEdge | Measure-Object).Count
    Log "ERROR: Edge window not found after 40s (widget edge processes: $n)"; exit 1
}

$HWND_BOTTOM = [IntPtr]1
$SWP_NOSIZE = 0x1; $SWP_NOMOVE = 0x2; $SWP_NOACTIVATE = 0x10; $SWP_FRAMECHANGED = 0x20
$progman = [W]::FindWindow('Progman', [NullString]::Value)

function Pin-ToDesktop($h) {
    # Owned by the desktop -> stays visible on Win+D; APPWINDOW gives it a taskbar button
    [W]::ShowWindow($h, 0) | Out-Null
    [W]::SetWindowLongPtr($h, -8, $progman) | Out-Null          # GWL_HWNDPARENT = owner
    $ex = [W]::GetWindowLong($h, -20)
    $ex = ($ex -bor 0x40000) -band (-bnot 0x80)                  # APPWINDOW on (taskbar button), TOOLWINDOW off
    [W]::SetWindowLong($h, -20, $ex) | Out-Null
    [W]::SetWindowPos($h, $HWND_BOTTOM, 0, 0, 0, 0, $SWP_NOSIZE -bor $SWP_NOMOVE -bor $SWP_NOACTIVATE -bor $SWP_FRAMECHANGED) | Out-Null
    [W]::ShowWindow($h, 4) | Out-Null                            # SW_SHOWNOACTIVATE
    [W]::SetWindowText($h, $WindowName) | Out-Null          # name shown on the taskbar (the page title stays empty so the top bar is blank)
    Log "pinned hwnd=$h owner=$progman"
}
Pin-ToDesktop $hwnd
Set-Frameless $hwnd $true

# Bring the widget in front of other windows for a few seconds (on launch, or from the tray icon),
# otherwise it would sink behind whatever window is active and look like it never opened.
$showUntil = [DateTime]::MinValue
function Show-Widget([int]$sec = 8) {
    $h = $script:hwnd; if ($h -eq [IntPtr]::Zero) { return }
    if ([W]::IsIconic($h)) { [W]::ShowWindow($h, 9) | Out-Null }
    [W]::SetWindowPos($h, [IntPtr](-1), 0, 0, 0, 0, 0x1 -bor 0x2 -bor 0x40) | Out-Null   # TOPMOST + SHOW
    [W]::SetWindowPos($h, [IntPtr](-2), 0, 0, 0, 0, 0x1 -bor 0x2 -bor 0x40) | Out-Null   # back to normal, stays on top for now
    [W]::SetForegroundWindow($h) | Out-Null
    $script:showUntil = (Get-Date).AddSeconds($sec)
}

# Tray icon: click = show the widget, right click = menu
$trayCmd = $null
$tray = New-Object System.Windows.Forms.NotifyIcon
$IconFile = Join-Path $Here 'cat.ico'
if (Test-Path $IconFile) { try { $tray.Icon = New-Object System.Drawing.Icon($IconFile, 32, 32) } catch {} }
if (-not $tray.Icon) { try {
    $bmp = New-Object System.Drawing.Bitmap 32, 32
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'
    $g.FillEllipse((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(91, 141, 239))), 1, 1, 30, 30)
    $f = New-Object System.Drawing.Font('Segoe UI', 15, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $sf = New-Object System.Drawing.StringFormat; $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
    $g.DrawString('C', $f, [System.Drawing.Brushes]::White, (New-Object System.Drawing.RectangleF(0, 1, 32, 32)), $sf)
    $tray.Icon = [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
} catch { $tray.Icon = [System.Drawing.SystemIcons]::Application } }

# shortcuts (desktop + startup) use the cat icon too; fixes older installs after an auto-update
function Set-ShortcutIcons {
    if (-not (Test-Path $IconFile) -or (Test-Path (Join-Path $Here '.dev'))) { return }   # a dev copy never touches the real shortcuts
    $shell = New-Object -ComObject WScript.Shell
    foreach ($l in @((Join-Path ([Environment]::GetFolderPath('Desktop')) 'CAT Schedule Widget.lnk'), $Lnk)) {
        try { if (Test-Path $l) {
            $sc = $shell.CreateShortcut($l); $vbs = Join-Path $Here 'launch.vbs'; $dirty = $false
            if ($sc.IconLocation -ne "$IconFile,0") { $sc.IconLocation = "$IconFile,0"; $dirty = $true }
            if ((Test-Path $vbs) -and ($sc.TargetPath -notlike '*wscript.exe' -or $sc.Arguments -ne "`"$vbs`"")) { $sc.TargetPath = 'wscript.exe'; $sc.Arguments = "`"$vbs`""; $dirty = $true }
            if ($dirty) { $sc.Save() } } } catch {}
    }
}
Set-ShortcutIcons
$tray.Text = "CAT 일정 위젯 v$AppVersion"
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$menu.Items.Add('위젯 보이기', $null, { $script:trayCmd = 'show' }) | Out-Null
$menu.Items.Add('새로고침', $null, { $script:trayCmd = 'reload' }) | Out-Null
$menu.Items.Add('스케줄러 사이트 열기', $null, { $script:trayCmd = 'site' }) | Out-Null
$menu.Items.Add('문제 보고 (오류 로그 복사)', $null, { $script:trayCmd = 'report' }) | Out-Null
$menu.Items.Add("업데이트 확인 (현재 v$AppVersion)", $null, { $script:trayCmd = 'update' }) | Out-Null
$menu.Items.Add('-') | Out-Null
$menu.Items.Add('종료', $null, { $script:trayCmd = 'exit' }) | Out-Null
$tray.ContextMenuStrip = $menu
$tray.add_MouseClick({ param($s, $e) if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) { $script:trayCmd = 'show' } })
$tray.Visible = $true
$firstRunFlag = Join-Path $Here 'first-run-done'
if (-not (Test-Path $firstRunFlag)) {
    $tray.ShowBalloonTip(6000, 'CAT 일정 위젯', '바탕화면 위젯으로 실행됐어요. 다른 창 뒤에 숨으면 이 아이콘을 누르거나 Win+D로 볼 수 있어요.', 'Info')
    Set-Content $firstRunFlag '1'
}
Show-Widget 6

# Keep it on the desktop layer and remember where the user puts it
$updateReady = $null
function Do-UpdateCheck([switch]$Manual) {
    $script:nextUpdateCheck = (Get-Date).AddMinutes(30)
    $v = Update-Available
    if (-not $v) { if ($Manual) { $tray.ShowBalloonTip(3000, 'CAT 일정 위젯', "최신 버전이에요 (v$AppVersion)", 'Info') }; return }
    if (-not $Manual) {                     # found in the background: let the widget show a [업데이트] button
        if ($script:updateReady -ne $v) {
            $script:updateReady = $v
            Log "update available: $v"
            $tray.ShowBalloonTip(5000, 'CAT 일정 위젯', "새 버전 v$v 이 있어요. 위젯의 [업데이트] 버튼을 누르면 바로 적용돼요.", 'Info')
        }
        return
    }
    Apply-Update $v
}
function Apply-Update([string]$v) {
    $tray.ShowBalloonTip(3000, 'CAT 일정 위젯', "v$v 으로 업데이트하고 다시 켭니다…", 'Info')
    if (Install-Update $v) {
        $tray.Visible = $false; $tray.Dispose(); $listener.Stop()
        Restart-Self; exit 0
    } else { $tray.ShowBalloonTip(4000, 'CAT 일정 위젯', '업데이트에 실패했어요. 문제 보고로 로그를 보내주세요.', 'Warning') }
}
$nextUpdateCheck = (Get-Date).AddMinutes(30)

$lastSaved = ''
$lastSize = ''
while ($true) {
    Pump-Requests 150
    [System.Windows.Forms.Application]::DoEvents()
    if ((Get-Date) -gt $nextUpdateCheck) { Do-UpdateCheck }
    if ([W]::IsWindow($hwnd) -and [W]::Title($hwnd) -ne $WindowName) { [W]::SetWindowText($hwnd, $WindowName) | Out-Null }   # Edge resets it on reload
    if ($trayCmd) {
        $cmd = $trayCmd; $trayCmd = $null
        switch ($cmd) {
            'show'   { Show-Widget 8 }
            'site'   { Start-Process $SiteUrl }
            'update' { Do-UpdateCheck -Manual }
            'updatenow' { if ($updateReady) { Apply-Update $updateReady } else { Do-UpdateCheck -Manual } }
            'report' { Start-Process powershell -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$(Join-Path $Here 'report.ps1')`"" }
            'reload' { $tray.Visible = $false; $tray.Dispose(); $listener.Stop(); Restart-Self; exit 0 }
            'exit'   { $tray.Visible = $false; $tray.Dispose(); Stop-OurEdge; $listener.Stop(); exit 0 }
        }
    }
    if (-not [W]::IsWindow($hwnd)) {
        if ((Get-OurEdge | Measure-Object).Count -eq 0) { Log 'Edge closed (widget window closed), exiting'; $tray.Visible = $false; $tray.Dispose(); $listener.Stop(); break }
        $h2 = Find-Widget
        if ($h2 -ne [IntPtr]::Zero) { $hwnd = $h2; Pin-ToDesktop $hwnd; $lastSize = '' }
        continue
    }
    if ([W]::IsIconic($hwnd)) { $showUntil = [DateTime]::MinValue; continue }   # minimized: leave it down until it is reopened from the taskbar
    if ([W]::GetForegroundWindow() -eq $hwnd) { $showUntil = [DateTime]::MinValue }   # once you use it, normal rules apply
    if (-not $editing -and (Get-Date) -gt $showUntil -and [W]::GetForegroundWindow() -ne $hwnd) {
        # whenever you're not using it, push it back down behind everything
        [W]::SetWindowPos($hwnd, $HWND_BOTTOM, 0, 0, 0, 0, $SWP_NOSIZE -bor $SWP_NOMOVE -bor $SWP_NOACTIVATE) | Out-Null
    }
    $r = New-Object W+RECT
    [W]::GetWindowRect($hwnd, [ref]$r) | Out-Null
    $cur = "$($r.L),$($r.T),$($r.R - $r.L),$($r.B - $r.T)"
    $size = "$($r.R - $r.L)x$($r.B - $r.T)"
    if (-not $editing -and $size -ne $lastSize) { $lastSize = $size; Set-Frameless $hwnd $true }
    if ($cur -ne $lastSaved -and ($r.R - $r.L) -gt 200) {
        $lastSaved = $cur
        [pscustomobject]@{ X = $r.L; Y = $r.T; W = $r.R - $r.L; H = $r.B - $r.T } |
            ConvertTo-Json | Set-Content $StateFile
    }
}
