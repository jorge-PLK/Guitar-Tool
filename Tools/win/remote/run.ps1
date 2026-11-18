# Arranca en consola el producto instalado y captura salida y codigo.
# Salida: "TF:RUN <arch> <codigo>" y la salida del programa indentada. Codigo 1 si algun programa falla.
param(
    [string]$Product = "tf-smoke",
    [string]$Arch = "both"
)
$ErrorActionPreference = "Continue"
. "$PSScriptRoot\common.ps1"

$failed = $false
foreach ($a in (Get-Archs $Arch)) {
    $exe = Join-Path (Join-Path $InstallRoot $a) "$Product.exe"
    $lines = & $exe 2>&1 | ForEach-Object { "$_" }
    $rc = $LASTEXITCODE
    Write-Output "TF:RUN $a $rc"
    $lines | ForEach-Object { Write-Output "  [$a] $_" }
    if ($rc -ne 0) { $failed = $true }
}
if ($failed) { exit 1 }
exit 0
