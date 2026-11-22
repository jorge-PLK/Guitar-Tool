# Compila la app Flutter tf_probe (windows release) y junta las DLL del nucleo junto al .exe. EN EL PC (lo lanza pc.sh app).
# Escribe out\app.log y out\app.done. Todo estado de Flutter/Dart va a $P9 (Set-FlutterEnv).
. "$PSScriptRoot\common.ps1"
Set-FlutterEnv
$log = Join-Path $Out "app.log"
$done = Join-Path $Out "app.done"
Remove-Item $done -ErrorAction SilentlyContinue
$rc = 1
"TF:start $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))" | Out-File $log -Encoding ascii
try {
    if (-not (Test-Path $Flutter)) { throw "falta $Flutter" }
    if (-not (Test-Path (Join-Path $CoreOut "AppCoreFFI.dll"))) { throw "falta out\core\AppCoreFFI.dll (pc.sh core)" }
    Push-Location $AppDir
    $sw = [Diagnostics.Stopwatch]::StartNew()
    & $Flutter --no-version-check build windows --release 2>&1 | ForEach-Object { "$_" } | Out-File $log -Encoding ascii -Append
    $brc = $LASTEXITCODE
    $sw.Stop()
    Pop-Location
    "TF:flutter build rc=$brc $([math]::Round($sw.Elapsed.TotalSeconds,1)) s" | Out-File $log -Encoding ascii -Append
    if ($brc -ne 0) { throw "flutter build fallo" }
    $rel = Join-Path $AppDir "build\windows\x64\runner\Release"
    $exe = Join-Path $rel "tf_probe.exe"
    if (-not (Test-Path $exe)) { throw "no existe $exe" }
    $n = 0
    Get-ChildItem $CoreOut -Filter *.dll | ForEach-Object { Copy-Item $_.FullName $rel -Force; $n++ }
    $size = (Get-ChildItem $rel -Recurse -File | Measure-Object Length -Sum).Sum
    "TF:tf_probe.exe $([math]::Round((Get-Item $exe).Length / 1KB)) KB; DLL copiadas: $n; Release total $([math]::Round($size / 1MB,1)) MB" | Out-File $log -Encoding ascii -Append
    "TF:release $rel" | Out-File $log -Encoding ascii -Append
    $rc = 0
} catch {
    "error: $_" | Out-File $log -Encoding ascii -Append
} finally {
    "$rc" | Out-File $done -Encoding ascii
}
exit $rc
