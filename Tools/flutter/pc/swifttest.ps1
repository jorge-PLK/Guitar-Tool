# swift test con filtro de un paquete sobre el clon f7 (sin la suite entera). Uso: swifttest.ps1 -Package VideoKit -Filter Clase/test
param([string]$Package = "VideoKit", [string]$Filter = "")
. "$PSScriptRoot\common.ps1"
$env:Path = "$TfRtl;" + $env:Path
$pkgPath = Join-Path $Repo "Packages\$Package"
$a = @("--filter", $Filter)
& swift build --build-tests @(Get-SwiftArgs "debug" $pkgPath) 2>&1 | ForEach-Object { "$_" } | Select-String -Pattern "error:|Compiling|Build complete" | Select-Object -Last 8
$env:USERPROFILE = $RealUserProfile
& swift test --skip-build @(Get-SwiftArgs "debug" $pkgPath) @a 2>&1 | ForEach-Object { "$_" }
exit $LASTEXITCODE
