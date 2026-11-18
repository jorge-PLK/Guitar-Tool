# Compila el paquete en C:\tf para una o las dos arquitecturas.
# Salida: lineas "TF:BUILD <arch> OK|FALLO <segundos>" seguidas de la salida de swift.
# Codigo: 0 bien, 2 falla la compilacion (o no hay Package.swift).
param(
    [string]$Package = "Tools/win/smoke",
    [string]$Arch = "both"
)
$ErrorActionPreference = "Continue"
. "$PSScriptRoot\common.ps1"

$pkgPath = Join-Path $TfRoot ($Package -replace "/", "\")
if (-not (Test-Path (Join-Path $pkgPath "Package.swift"))) {
    Write-Output "TF:BUILD - FALLO 0"
    Write-Output "error: no existe Package.swift en $pkgPath"
    exit 2
}

$failed = $false
foreach ($a in (Get-Archs $Arch)) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $lines = & swift build --package-path $pkgPath @(Get-SwiftArgs $a) 2>&1 | ForEach-Object { "$_" }
    $rc = $LASTEXITCODE
    $sw.Stop()
    $secs = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    if ($rc -eq 0) {
        Write-Output "TF:BUILD $a OK $secs"
    } else {
        Write-Output "TF:BUILD $a FALLO $secs"
        $failed = $true
    }
    $lines | ForEach-Object { Write-Output "  [$a] $_" }
    if ($failed) { break }
}
if ($failed) { exit 2 }
exit 0
