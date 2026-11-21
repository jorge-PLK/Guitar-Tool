# Comun a los scripts remotos de Tools/win/build.sh. ASCII puro, PowerShell 5.1.
$env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User")

$TfRoot = "C:\tf"
$InstallRoot = "C:\ToneForge"

# Argumentos de swift build para una arquitectura ("arm64" o "x64").
function Get-SwiftArgs([string]$arch) {
    $a = @("-c", "release", "--static-swift-stdlib")
    if ($arch -eq "x64") { $a += @("--arch", "x86_64") }
    if (Test-Path "C:\tf-libs\$arch") {
        # curl.lib (alias de libcurl) no arrastra sus dependencias: zlib, brotli y libxml2 se nombran a mano.
        $a += @("-Xlinker", "/LIBPATH:C:\tf-libs\$arch")
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
$OrtRoot = "C:\tf-ort"
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
    $dst = "C:\tf-libs\$arch"
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
