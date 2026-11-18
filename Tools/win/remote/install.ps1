# Copia el producto (exe, dll y carpetas .resources) a C:\ToneForge\<arch>\ y lee la maquina PE.
# Salida: "TF:PE <arch> <0xNNNN> <ok|ERROR> <ruta>". Codigo 0 bien, 2 si falta el exe o la maquina no coincide.
param(
    [string]$Package = "Tools/win/smoke",
    [string]$Product = "tf-smoke",
    [string]$Arch = "both"
)
$ErrorActionPreference = "Continue"
. "$PSScriptRoot\common.ps1"

$pkgPath = Join-Path $TfRoot ($Package -replace "/", "\")
$expected = @{ "arm64" = 0xAA64; "x64" = 0x8664 }
$bad = $false

foreach ($a in (Get-Archs $Arch)) {
    $bin = (& swift build --package-path $pkgPath @(Get-SwiftArgs $a) --show-bin-path 2>$null | Select-Object -Last 1)
    $src = Join-Path $bin "$Product.exe"
    if (-not (Test-Path $src)) {
        Write-Output "TF:PE $a 0x0000 ERROR no existe $src"
        $bad = $true
        continue
    }
    $dest = Join-Path $InstallRoot $a
    if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
    New-Item -ItemType Directory -Force $dest | Out-Null
    Copy-Item $src $dest
    Get-ChildItem $bin -Filter "*.dll" | Copy-Item -Destination $dest
    Get-ChildItem $bin -Directory -Filter "*.resources" | Copy-Item -Destination $dest -Recurse

    $exe = Join-Path $dest "$Product.exe"
    $bytes = [IO.File]::ReadAllBytes($exe)
    $pe = [BitConverter]::ToInt32($bytes, 0x3C)
    $machine = [BitConverter]::ToUInt16($bytes, $pe + 4)
    $hex = "0x{0:X4}" -f $machine
    if ($machine -eq $expected[$a]) {
        Write-Output "TF:PE $a $hex ok $exe"
    } else {
        Write-Output ("TF:PE $a $hex ERROR esperada 0x{0:X4}" -f $expected[$a])
        $bad = $true
    }
}
if ($bad) { exit 2 }
exit 0
