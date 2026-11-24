# Comun a los scripts remotos de Tools/win/build.sh. ASCII puro, PowerShell 5.1.
$env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User")
# SDKROOT (lo pone el instalador de Swift) puede no estar heredado: recargar del registro o buscar la version mas alta.
if (-not $env:SDKROOT) {
    $env:SDKROOT = [Environment]::GetEnvironmentVariable("SDKROOT","Machine")
    if (-not $env:SDKROOT) { $env:SDKROOT = [Environment]::GetEnvironmentVariable("SDKROOT","User") }
}
if (-not $env:SDKROOT -or -not (Test-Path $env:SDKROOT)) {
    $p = Get-ChildItem "$env:LOCALAPPDATA\Programs\Swift\Platforms" -Directory -ErrorAction SilentlyContinue |
        Sort-Object { try { [version]$_.Name } catch { [version]"0.0" } } -Descending | Select-Object -First 1
    if ($p) { $env:SDKROOT = "$($p.FullName)\Windows.platform\Developer\SDKs\Windows.sdk" }
}
# Si link.exe de MSVC no esta en el PATH (SwiftPM lo exige), anteponer el de la version mas alta de VS.
if (-not (Get-Command link -ErrorAction SilentlyContinue)) {
    $vsw = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vsw) {
        $vs = & $vsw -products * -latest -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1
        if (-not $vs) { $vs = & $vsw -products * -latest -property installationPath | Select-Object -First 1 }
        if ($vs -and (Test-Path "$vs\VC\Tools\MSVC")) {
            $lk = Get-ChildItem "$vs\VC\Tools\MSVC" -Directory | Sort-Object { [version]$_.Name } -Descending |
                Where-Object { Test-Path "$($_.FullName)\bin\Hostx64\x64\link.exe" } | Select-Object -First 1
            if ($lk) { $env:Path = "$($lk.FullName)\bin\Hostx64\x64;" + $env:Path }
        }
    }
}

# Unidad de trabajo: C: en la VM; pass.ps1 pone TF_DRIVE a la unidad del clon (p. ej. D:) en el PC.
$TfDrive = if ($env:TF_DRIVE) { $env:TF_DRIVE.TrimEnd('\') } else { "C:" }
$TfRoot = "$TfDrive\tf"
$InstallRoot = "$TfDrive\ToneForge"
if (-not $env:TF_WEBVIEW2_DIR) { $env:TF_WEBVIEW2_DIR = "$TfDrive\tf-webview2" }   # lo lee WinApp/Package.swift

# Argumentos de swift build para una arquitectura ("arm64" o "x64").
function Get-SwiftArgs([string]$arch) {
    $a = @("-c", "release", "--static-swift-stdlib")
    if ($arch -eq "x64") { $a += @("--arch", "x86_64") }
    if (Test-Path "$TfDrive\tf-libs\$arch") {
        # curl.lib (alias de libcurl) no arrastra sus dependencias: zlib, brotli y libxml2 se nombran a mano.
        $a += @("-Xlinker", "/LIBPATH:$TfDrive\tf-libs\$arch")
        foreach ($l in @("zlibstatic.lib", "brotlidec.lib", "brotlicommon.lib", "libxml2s.lib")) { $a += @("-Xlinker", $l) }
    }
    return $a
}

function Get-Archs([string]$arch) {
    if ($arch -eq "both") { return @("arm64", "x64") }
    return @($arch)
}

# ONNX Runtime: carpeta persistente C:\tf-ort\<arch> (la rellena Tools/win/build.sh desde Vendor/win/ort; --clean no la
# borra). Si el ejecutable (o .dll de tests) lleva COnnxRuntime (busca el nombre OrtGetApiBase), deja las DLL junto a el: System32 trae otra
# onnxruntime.dll que se carga antes que el PATH. COnnxRuntime carga la DLL en ejecucion (sin import lib). Devuelve $true si copio.
$OrtRoot = "$TfDrive\tf-ort"
function Copy-OrtDlls([string]$arch, [string]$binDir, [string]$exe) {
    $src = Join-Path $OrtRoot $arch
    if (-not (Test-Path $src) -or -not (Test-Path $exe)) { return $false }
    $bytes = [IO.File]::ReadAllBytes($exe)
    $text = [Text.Encoding]::GetEncoding(28591).GetString($bytes)
    if (-not $text.Contains("OrtGetApiBase")) { return $false }
    Get-ChildItem $src -Filter "*.dll" | Copy-Item -Destination $binDir -Force
    return $true
}

# Enlace estatico con FoundationNetworking: los modulos de curl/zlib/libxml2 piden curl.lib, zlib.lib y
# libxml2.lib, y el toolchain trae libcurl.lib, zlibstatic.lib y libxml2s.lib en swift_static. Copia con esos nombres a
# C:\tf-libs\<arch> y Get-SwiftArgs lo anade como -Xlinker /LIBPATH (LIB no vale: tapa la deteccion de MSVC). Nada en los paquetes. Idempotente.
function Initialize-StaticNetLibs([string]$arch) {
    $sdk = Get-ChildItem "$env:LOCALAPPDATA\Programs\Swift\Platforms" -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
    if (-not $sdk) { return }
    $dirName = if ($arch -eq "x64") { "x86_64" } else { "aarch64" }
    $src = Join-Path $sdk.FullName "Windows.platform\Developer\SDKs\Windows.sdk\usr\lib\swift_static\windows\$dirName"
    if (-not (Test-Path $src)) { return }
    $dst = "$TfDrive\tf-libs\$arch"
    New-Item -ItemType Directory -Force $dst | Out-Null
    $map = @{ "libcurl.lib" = @("curl.lib"); "zlibstatic.lib" = @("zlib.lib", "z.lib"); "libxml2s.lib" = @("libxml2.lib", "xml2.lib"); "brotlidec.lib" = @(); "brotlicommon.lib" = @() }
    foreach ($k in $map.Keys) {
        $f = Join-Path $src $k
        if (-not (Test-Path $f)) { continue }
        $d = Join-Path $dst $k
        if (-not (Test-Path $d) -or (Get-Item $d).Length -ne (Get-Item $f).Length) { Copy-Item $f $d -Force }
        foreach ($n in $map[$k]) {
            $d = Join-Path $dst $n
            if (-not (Test-Path $d) -or (Get-Item $d).Length -ne (Get-Item $f).Length) { Copy-Item $f $d -Force }
        }
    }
}
