# P9 7h: compila (release, windows x64) video\vp_fvp (fvp/mdk). EN EL PC (lo lanza pc.sh video).
# Escribe out\video.log (TF:...), out\video\build.log (build completo) y out\video.done.
. "$PSScriptRoot\common.ps1"
Set-FlutterEnv
$log = Join-Path $Out "video.log"
$done = Join-Path $Out "video.done"
$VOut = Join-Path $Out "video"
New-Item -ItemType Directory -Force $VOut | Out-Null
Remove-Item $done -ErrorAction SilentlyContinue
function L($m) { "$m" | Out-File $log -Encoding ascii -Append }
"TF:start $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))" | Out-File $log -Encoding ascii
$rc = 1
try {
    if (-not (Test-Path $Flutter)) { throw "falta $Flutter" }
    L "TF:flutter $((& $Flutter --no-version-check --version 2>&1 | Select-Object -First 1))"
    $dir = Join-Path $Src "Probes\P9-flutter\video\vp_fvp"
    $clog = Join-Path $VOut "build.log"
    "TF:start" | Out-File $clog -Encoding ascii
    Push-Location $dir
    $sw = [Diagnostics.Stopwatch]::StartNew()
    & $Flutter --no-version-check pub get 2>&1 | ForEach-Object { "$_" } | Out-File $clog -Encoding ascii -Append
    $prc = $LASTEXITCODE
    $brc = 99
    if ($prc -eq 0) {
        & $Flutter --no-version-check build windows --release 2>&1 | ForEach-Object { "$_" } | Out-File $clog -Encoding ascii -Append
        $brc = $LASTEXITCODE
    }
    $sw.Stop()
    Pop-Location
    $secs = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    $rel = Join-Path $dir "build\windows\x64\runner\Release"
    $exe = Join-Path $rel "vp_fvp.exe"
    if ($prc -ne 0 -or $brc -ne 0 -or -not (Test-Path $exe)) {
        L "TF:vp_fvp compila=NO pubget=$prc build=$brc ${secs}s (log out\video\build.log)"
        foreach ($e in (Select-String -Path $clog -Pattern 'error|fatal|not found|Cannot|failed' | Select-Object -First 8)) { L "TF:ERR $($e.Line.Trim())" }
    } else {
        $dlls = @(Get-ChildItem $rel -Filter *.dll | ForEach-Object Name) -join ','
        L "TF:vp_fvp compila=SI ${secs}s dlls=[$dlls]"
    }
    $rc = 0
} catch {
    L "error: $_"
} finally {
    "$rc" | Out-File $done -Encoding ascii
}
exit $rc
