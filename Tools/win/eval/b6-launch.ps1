# B6: cierre ordenado (WM_CLOSE) con una descarga por enlace en marcha. Local (PC o sesion interactiva). Solo ASCII. PS 5.1 y 7.
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File Tools\win\eval\b6-launch.ps1 [-Work C:\tf-qa\b6] [-Exe C:\ToneForge\x64\ToneForge.exe]
# Mide cuanto tardan en desaparecer ToneForge.exe, yt-dlp.exe y ffmpeg.exe tras WM_CLOSE (tope 3.5 s) y que tras reabrir no haya trabajo en marcha.
# --audio simulated y --camera simulated: no toca audio ni camara reales. Ultima linea: DONE b6 n/m (skip k).
param([string]$Work = "", [string]$Exe = "", [double]$MaxCloseSec = 3.5)
$ErrorActionPreference = "Continue"
$TfDrive = if ($env:TF_DRIVE) { $env:TF_DRIVE.TrimEnd('\') } else { "C:" }   # pass.ps1 la pone a la unidad del clon
if (-not $Work) { $Work = "$TfDrive\tf-qa\b6" }; if (-not $Exe) { $Exe = "$TfDrive\ToneForge\x64\ToneForge.exe" }
$script:ok = 0; $script:bad = 0; $script:skip = 0
function Chk($n, $c, $d) { if ($c) { $script:ok++; Write-Output "eval| OK $n $d" } else { $script:bad++; Write-Output "eval| FAIL $n $d" } }
function Finish { Write-Output "DONE b6 $($script:ok)/$($script:ok + $script:bad) (skip $($script:skip))"; exit 0 }
if (-not (Test-Path $Exe)) { Write-Output "B6 SINAPP: falta $Exe"; exit 3 }
$reach = $false; try { $c = New-Object Net.Sockets.TcpClient; $reach = $c.ConnectAsync("www.youtube.com", 443).Wait(4000); $c.Close() } catch {}
if (-not $reach) { $script:skip++; Write-Output "eval| SKIP b6 sin red a www.youtube.com:443: no se puede iniciar una descarga real"; Finish }
foreach ($n in "ToneForge", "yt-dlp", "ffmpeg") { Get-Process -Name $n -ErrorAction SilentlyContinue | Stop-Process -Force }
Remove-Item -Recurse -Force $Work -ErrorAction SilentlyContinue
$proj = Join-Path $Work "projects"; $sup = Join-Path $Work "support"
New-Item -ItemType Directory -Force $proj, $sup | Out-Null
$body = [IO.File]::ReadAllText((Join-Path $PSScriptRoot "b6.js"), [Text.Encoding]::UTF8)
$utf8 = New-Object Text.UTF8Encoding($false)
function Start-App($phase, $jobId) {
    $js = Join-Path $Work "b6-$phase.js"; $log = Join-Path $Work "app-$phase.log"
    [IO.File]::WriteAllText($js, "globalThis.B6_PHASE='$phase'; globalThis.B6_JOBID='$jobId';`n$body", $utf8)
    $env:TF_LOG_FILE = $log
    $al = @("--projects-folder", $proj, "--support-dir", $sup, "--audio", "simulated", "--camera", "simulated", "--screen", "library", "--window", "1440x900", "--eval-file", $js, "--eval-delay", "6")
    return (Start-Process -FilePath $Exe -ArgumentList $al -PassThru)
}
function Get-Log($phase) { $f = Join-Path $Work "app-$phase.log"; if (Test-Path $f) { return @(Get-Content $f -Encoding UTF8 | Select-String -Pattern "eval\|" | ForEach-Object { $_.Line }) } else { return @() } }
Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; using System.Text; public static class B6Win { public delegate bool EnumProc(IntPtr h, IntPtr l); [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, IntPtr l); [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid); [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h); [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l); public static int Close(uint pid) { int n = 0; EnumWindows((h, l) => { uint p; GetWindowThreadProcessId(h, out p); if (p == pid && IsWindowVisible(h)) { PostMessage(h, 0x0010, IntPtr.Zero, IntPtr.Zero); n++; } return true; }, IntPtr.Zero); return n; } }'

# Fase a: descarga en marcha y cierre
$app = Start-App "a" ""
$jobId = ""; $deadline = (Get-Date).AddSeconds(240); $live = @()
while ((Get-Date) -lt $deadline) {
    $l = Get-Log "a"
    $m = $l | Where-Object { $_ -match "INFO jobid (\S+)" } | Select-Object -First 1
    if ($m -and $m -match "INFO jobid (\S+)") { $jobId = $Matches[1] }
    $live = @(Get-Process -Name "yt-dlp", "ffmpeg" -ErrorAction SilentlyContinue)
    if ($live.Count -gt 0) { break }
    if ($app.HasExited) { break }
    Start-Sleep -Milliseconds 250
}
Chk "b6.proceso-hijo-vivo" ($live.Count -gt 0) ("vivos: " + (($live | ForEach-Object { $_.ProcessName }) -join ","))
if ($live.Count -eq 0) { Get-Log "a" | ForEach-Object { Write-Output $_ }; $app | Stop-Process -Force -ErrorAction SilentlyContinue; Finish }
Start-Sleep -Seconds 2
$tracked = @($app) + @(Get-Process -Name "yt-dlp", "ffmpeg" -ErrorAction SilentlyContinue)
$sw = [Diagnostics.Stopwatch]::StartNew()
$posted = [B6Win]::Close([uint32]$app.Id)
Chk "b6.wm-close-enviado" ($posted -gt 0) "ventanas=$posted"
$gone = @{}
while ($sw.Elapsed.TotalSeconds -lt 20 -and $gone.Count -lt $tracked.Count) {
    foreach ($p in $tracked) { $k = "$($p.ProcessName)#$($p.Id)"; if (-not $gone.ContainsKey($k) -and -not (Get-Process -Id $p.Id -ErrorAction SilentlyContinue)) { $gone[$k] = [math]::Round($sw.Elapsed.TotalSeconds, 2) } }
    Start-Sleep -Milliseconds 50
}
foreach ($p in $tracked) {
    $k = "$($p.ProcessName)#$($p.Id)"
    if ($gone.ContainsKey($k)) { Chk "b6.cierre.$($p.ProcessName)" ($gone[$k] -le $MaxCloseSec) "$($gone[$k]) s (tope $MaxCloseSec)" }
    else { Chk "b6.cierre.$($p.ProcessName)" $false "sigue vivo tras 20 s; se mata"; Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
}
Write-Output "eval| INFO b6 jobId=$jobId"
# Fase b: reabrir
Start-Sleep -Seconds 2
$app2 = Start-App "b" $jobId
$until = (Get-Date).AddSeconds(90); $dn = $false
while ((Get-Date) -lt $until -and -not $dn) { Start-Sleep -Seconds 2; $dn = [bool](Get-Log "b" | Where-Object { $_ -match "DONE b6part" }) }
Get-Log "b" | ForEach-Object { Write-Output $_ }
$d = Get-Log "b" | Where-Object { $_ -match "DONE b6part \S+ (\d+)/(\d+)" } | Select-Object -Last 1
if ($d -and $d -match "DONE b6part \S+ (\d+)/(\d+)") { $script:ok += [int]$Matches[1]; $script:bad += ([int]$Matches[2] - [int]$Matches[1]) } else { $script:bad++; Write-Output "eval| FAIL b6 fase b sin linea DONE" }
$rest = @(Get-Process -Name "yt-dlp", "ffmpeg" -ErrorAction SilentlyContinue)
Chk "b6.sin-hijos-tras-reabrir" ($rest.Count -eq 0) "vivos=$($rest.Count)"
$app2 | Stop-Process -Force -ErrorAction SilentlyContinue
Finish
