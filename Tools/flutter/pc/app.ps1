# Compila la app Windows (release) con el Flutter de P9 y deja junto al .exe el AppCoreFFI.dll y sus DLL (salida de core.ps1).
. "$PSScriptRoot\common.ps1"
if (-not (Test-Path (Join-Path $Stage "AppCoreFFI.dll"))) { Stop-Step 1 "falta $Stage\AppCoreFFI.dll: ejecuta antes el paso core" }
# FlutterApp\windows\CMakeLists.txt exige tf-separate.exe bajo Packages\StemKit\.build\*\release\ (el glob no ve el
# layout .build\out\Products de SwiftPM en Windows): se compila y se deja copia en .build\pcx64\release.
$sepArgs = @("build", "--product", "tf-separate") + @(Get-SwiftArgs "release" (Join-Path $Repo "Packages\StemKit"))
& swift @sepArgs 2>&1 | ForEach-Object { "$_" }
if ($LASTEXITCODE -ne 0) { Stop-Step 1 "swift build tf-separate" }
$sepBin = (& swift build --show-bin-path @(Get-SwiftArgs "release" (Join-Path $Repo "Packages\StemKit")) 2>$null | Select-Object -Last 1).Trim()
$sepDest = Join-Path $Repo "Packages\StemKit\.build\pcx64\release"
New-Item -ItemType Directory -Force $sepDest | Out-Null
Copy-Item (Join-Path $sepBin "tf-separate.exe") $sepDest -Force
Set-FlutterEnv
Set-Location $App
& $Flutter build windows --release 2>&1 | ForEach-Object { "$_" }
if ($LASTEXITCODE -ne 0) { Stop-Step 1 "flutter build windows" }
$exe = Get-Item $AppExe -ErrorAction SilentlyContinue
if (-not $exe) { Stop-Step 1 "no hay .exe en $ReleaseDir" }
Get-ChildItem $Stage -Filter *.dll | Copy-Item -Destination $ReleaseDir -Force
$core = Get-Item (Join-Path $ReleaseDir "AppCoreFFI.dll") -ErrorAction SilentlyContinue
if (-not $core) { Stop-Step 1 "AppCoreFFI.dll no quedo junto al exe" }
Write-Output "TF:exe $($exe.FullName) $($exe.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Output "TF:AppCoreFFI.dll $($core.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Output "TF:DLL junto al exe: $((Get-ChildItem $ReleaseDir -Filter *.dll | ForEach-Object Name) -join ' ')"
exit 0
