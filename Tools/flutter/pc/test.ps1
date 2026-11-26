# flutter analyze + flutter test + swift test de AppCore, parando en el primer fallo.
. "$PSScriptRoot\common.ps1"
Set-FlutterEnv
Set-Location $App
& $Flutter analyze 2>&1 | ForEach-Object { "$_" }
if ($LASTEXITCODE -ne 0) { Stop-Step 1 "flutter analyze" }
& $Flutter test 2>&1 | ForEach-Object { "$_" }
if ($LASTEXITCODE -ne 0) { Stop-Step 1 "flutter test" }
Write-Output "TF:flutter analyze + test correctos"
Set-Location $Repo
# Compilar con el HOME falso (SwiftPM escribe ~\.swiftpm) y ejecutar con el USERPROFILE real: los tests de carpetas conocidas
# (Musica) necesitan el perfil de verdad. Los tests escriben en $env:TEMP (bajo P9).
& swift build --build-tests @(Get-SwiftArgs "debug") 2>&1 | ForEach-Object { "$_" }
if ($LASTEXITCODE -ne 0) { Stop-Step 1 "swift build --build-tests" }
$env:USERPROFILE = $RealUserProfile
& swift test --skip-build @(Get-SwiftArgs "debug") 2>&1 | ForEach-Object { "$_" }
if ($LASTEXITCODE -ne 0) { Stop-Step 1 "swift test" }
Write-Output "TF:swift test AppCore correcto"
exit 0
