# Comun a core.ps1 y smoke.ps1 (P9 7b). ASCII puro, PowerShell 5.1. Se ejecuta EN EL PC.
# REGLA: todo lo que se escribe vive bajo $P9 (D:\Personal\Guitar-Tool\Temp\p9). Nada en C:, %TEMP% ni %LOCALAPPDATA%.
$ErrorActionPreference = "Continue"
# <P9>\src\Probes\P9-flutter\win -> <P9>
$P9 = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")).Path
$Src = Join-Path $P9 "src"
$Pkg = Join-Path $Src "Probes\P9-flutter\AppCoreFFI"
$Out = Join-Path $P9 "out"
$CoreOut = Join-Path $Out "core"
New-Item -ItemType Directory -Force $Out | Out-Null

# Solo lectura (Fase 7c).
$TfLibs = "D:\tf-libs\x64"
$TfOrt = "D:\tf-ort\x64"
$TfRtl = "D:\tf-rtl-x64"

# PATH de maquina + usuario (como la 7c) para ver swift.exe; temporales y cache de SwiftPM redirigidos a $P9.
$env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User")
$Tmp = Join-Path $P9 "tmp"
New-Item -ItemType Directory -Force $Tmp | Out-Null
$env:TEMP = $Tmp
$env:TMP = $Tmp
# SwiftPM escribe ~\.swiftpm (security\fingerprints, configuration) aunque se le pase --security-path: HOME falso en $P9.
$FakeHome = Join-Path $P9 "home"
New-Item -ItemType Directory -Force $FakeHome | Out-Null
$env:USERPROFILE = $FakeHome
$env:HOME = $FakeHome
$SpmDir = Join-Path $P9 "swiftpm"
New-Item -ItemType Directory -Force $SpmDir | Out-Null

# Flutter/Dart (P9 7d): TODO su estado y caches viven en $P9 (un solo sitio; lo usa app.ps1).
$Flutter = Join-Path $P9 "flutter\bin\flutter.bat"
$AppDir = Join-Path $Src "Probes\P9-flutter\app"
function Set-FlutterEnv() {
    $env:PUB_CACHE = Join-Path $P9 "pub-cache"
    $env:APPDATA = Join-Path $P9 "appdata"
    $env:LOCALAPPDATA = Join-Path $P9 "localappdata"
    $env:FLUTTER_SUPPRESS_ANALYTICS = "true"
    $env:BOT = "true"
    $env:DART_DISABLE_TELEMETRY = "1"
    # NuGet (plugins con CMake que bajan nuget.exe / paquetes, p. ej. WebView2): caches dentro de $P9.
    $env:NUGET_PACKAGES = Join-Path $P9 "nuget\packages"
    $env:NUGET_HTTP_CACHE_PATH = Join-Path $P9 "nuget\http-cache"
    $env:NUGET_PLUGINS_CACHE_PATH = Join-Path $P9 "nuget\plugins-cache"
    New-Item -ItemType Directory -Force $env:PUB_CACHE, $env:APPDATA, $env:LOCALAPPDATA, $env:NUGET_PACKAGES, $env:NUGET_HTTP_CACHE_PATH, $env:NUGET_PLUGINS_CACHE_PATH | Out-Null
}

# Flags de swift build para x64 (los de Tools/win/remote/common.ps1 adaptados a D:\).
function Get-SwiftArgs() {
    $a = @("-c", "release", "--arch", "x86_64", "--package-path", $Pkg,
           "--cache-path", (Join-Path $SpmDir "cache"),
           "--config-path", (Join-Path $SpmDir "config"),
           "--security-path", (Join-Path $SpmDir "security"))
    if ($env:P9_STATIC -eq "1") {
        # Runtime de Swift estatico: curl.lib (alias de libcurl) no arrastra sus dependencias; se nombran a mano.
        $a += @("--static-swift-stdlib", "-Xlinker", "/LIBPATH:$TfLibs")
        foreach ($l in @("zlibstatic.lib", "brotlidec.lib", "brotlicommon.lib", "libxml2s.lib")) { $a += @("-Xlinker", $l) }
    }
    return $a
}
