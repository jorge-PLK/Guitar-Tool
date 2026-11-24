# Compila el paquete en C:\tf para una o las dos arquitecturas.
# Salida: lineas "TF:BUILD <arch> OK|FALLO|TIMEOUT <segundos>" seguidas de la salida de swift.
# -TimeoutSec: tope total por arquitectura (por defecto 900; 0 = sin tope). Al vencer se mata el arbol
#   de procesos y sigue "TF:TIMEOUT <arch> total <procesos vivos tras matar> :: (compilando)".
# Codigo: 0 bien, 2 falla la compilacion, hay TIMEOUT (o no hay Package.swift).
param(
    [string]$Package = "Tools/win/smoke",
    [string]$Arch = "both",
    [int]$TimeoutSec = 900
)
$ErrorActionPreference = "Continue"
. "$PSScriptRoot\common.ps1"
. "$PSScriptRoot\limited.ps1"

$pkgPath = Join-Path $TfRoot ($Package -replace "/", "\")
if (-not (Test-Path (Join-Path $pkgPath "Package.swift"))) {
    Write-Output "TF:BUILD - FALLO 0"
    Write-Output "error: no existe Package.swift en $pkgPath"
    exit 2
}

$failed = $false
foreach ($a in (Get-Archs $Arch)) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    Initialize-StaticNetLibs $a
    $buildArgs = @("build", "--package-path", $pkgPath) + @(Get-SwiftArgs $a)
    $r = Invoke-Limited "swift" $buildArgs "$TfDrive\tf-build-$a.txt" $TimeoutSec 0
    $sw.Stop()
    $secs = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    if ($r.Reason -ne "") {
        Write-Output "TF:BUILD $a TIMEOUT $secs"
        Write-Output "TF:TIMEOUT $a $($r.Reason) $($r.Left) :: (compilando)"
        $failed = $true
    } elseif ($r.Rc -eq 0) {
        Write-Output "TF:BUILD $a OK $secs"
    } else {
        Write-Output "TF:BUILD $a FALLO $secs"
        $failed = $true
    }
    $r.Lines | ForEach-Object { Write-Output "  [$a] $_" }
    if ($failed) { break }
}
if ($failed) { exit 2 }
exit 0
