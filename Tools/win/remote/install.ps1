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
# Producto -> helpers que se instalan con el (tf-audio y tf-video se anaden aqui y en build.sh cuando toquen).
$helpers = @{ "ToneForge" = @(@{ Package = "Packages\StemKit"; Exe = "tf-separate" }) }

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
    # Paquetes con interfaz web (WinApp): la carpeta Web del paquete va como Web\ junto al .exe.
    $web = Join-Path $pkgPath "Web"
    if (Test-Path $web) { Copy-Item $web (Join-Path $dest "Web") -Recurse -Force }
    # alphaTab (pantalla Tablatura): se sirve como Web\alphaTab\ desde los recursos del Mac, sin duplicarlos en WinApp.
    $alpha = Join-Path $TfRoot "App\Resources\alphaTab"
    if ((Test-Path $web) -and (Test-Path $alpha)) {
        $alphaDest = Join-Path $dest "Web\alphaTab"
        New-Item -ItemType Directory -Force $alphaDest | Out-Null
        Copy-Item (Join-Path $alpha "*") $alphaDest -Recurse -Force
    }
    [void](Copy-OrtDlls $a $dest (Join-Path $dest "$Product.exe"))
    # Helpers de la app: ejecutables de otros paquetes que ToneForge lanza como procesos hijo y busca junto a su .exe.
    # build.sh compila antes esos paquetes. Los DLL del helper solo se copian si no estan ya (mandan los de la app).
    foreach ($h in $helpers[$Product]) {
        $hbin = (& swift build --package-path (Join-Path $TfRoot $h.Package) @(Get-SwiftArgs $a) --show-bin-path 2>$null | Select-Object -Last 1)
        $hsrc = Join-Path $hbin "$($h.Exe).exe"
        if (-not (Test-Path $hsrc)) {
            Write-Output "TF:HELPER $a $($h.Exe) FALTA"
            $bad = $true
            continue
        }
        Copy-Item $hsrc $dest -Force
        Get-ChildItem $hbin -Filter "*.dll" | Where-Object { -not (Test-Path (Join-Path $dest $_.Name)) } | Copy-Item -Destination $dest
        Write-Output "TF:HELPER $a $($h.Exe) ok"
    }

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
