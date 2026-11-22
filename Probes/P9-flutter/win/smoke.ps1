# Ejecuta el humo ffi-smoke-win.exe (carga AppCoreFFI.dll) con carpetas vacias en <P9>\run. Se ejecuta EN EL PC.
. "$PSScriptRoot\common.ps1"
$run = Join-Path $P9 "run"
if (Test-Path $run) { Remove-Item $run -Recurse -Force }
$projects = Join-Path $run "projects"
$support = Join-Path $run "support"
New-Item -ItemType Directory -Force $projects, $support | Out-Null
$exe = Join-Path $CoreOut "ffi-smoke-win.exe"
if (-not (Test-Path $exe)) { "error: falta $exe (ejecuta pc.sh core)"; exit 1 }
Push-Location $CoreOut
& $exe "--projects-folder" $projects "--support-dir" $support 2>&1 | ForEach-Object { "$_" } | Tee-Object -FilePath (Join-Path $Out "smoke.log")
$rc = $LASTEXITCODE
Pop-Location
"exit=$rc"
exit $rc
