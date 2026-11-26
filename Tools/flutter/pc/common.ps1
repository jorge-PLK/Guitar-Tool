# Comun a los .ps1 de Tools/flutter/pc.sh. ASCII puro, PowerShell 5.1. Se ejecuta EN EL PC (pc.sh los sube por scp).
# Los scripts viven en <P9>\pc1\ y el clon de la rama fase-7f en <P9>\f7; <P9> = D:\Personal\Guitar-Tool\Temp\p9.
# REGLA: todo lo que se escribe vive bajo $P9. Nada en C:, %TEMP% ni %LOCALAPPDATA%. No se toca el checkout de la 7c.
$ErrorActionPreference = "Continue"
$P9 = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Repo = Join-Path $P9 "f7"
$App = Join-Path $Repo "FlutterApp"
$Pkg = Join-Path $Repo "Packages\AppCore"
$Shots = Join-Path $Repo "Temp\flutter"
$Stage = Join-Path $P9 "f7core"
$ReleaseDir = Join-Path $App "build\windows\x64\runner\Release"
$AppExe = Join-Path $ReleaseDir "toneforge.exe"   # BINARY_NAME de FlutterApp\windows\CMakeLists.txt (junto a el hay helpers .exe)
$RemoteUrl = "https://github.com/jorge-PLK/Guitar-Tool.git"

# Solo lectura (Fase 7c).
$TfOrt = "D:\tf-ort\x64"
$TfRtl = "D:\tf-rtl-x64"

# PATH de maquina + usuario para ver swift.exe, git y link.exe; temporales y cache de SwiftPM dentro de $P9.
$env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User")
$Tmp = Join-Path $P9 "tmp"
New-Item -ItemType Directory -Force $Tmp | Out-Null
$env:TEMP = $Tmp
$env:TMP = $Tmp
# SwiftPM escribe ~\.swiftpm aunque se le pase --security-path: HOME falso en $P9.
$FakeHome = Join-Path $P9 "home"
New-Item -ItemType Directory -Force $FakeHome | Out-Null
$env:USERPROFILE = $FakeHome
$env:HOME = $FakeHome
$SpmDir = Join-Path $P9 "swiftpm"
New-Item -ItemType Directory -Force $SpmDir | Out-Null

# Flutter 3.50.1 de P9 (sin PATH) y todas sus caches en $P9.
$Flutter = Join-Path $P9 "flutter\bin\flutter.bat"
function Set-FlutterEnv() {
    $env:PUB_CACHE = Join-Path $P9 "pub-cache"
    $env:APPDATA = Join-Path $P9 "appdata"
    $env:LOCALAPPDATA = Join-Path $P9 "localappdata"
    $env:FLUTTER_SUPPRESS_ANALYTICS = "true"
    $env:BOT = "true"
    $env:DART_DISABLE_TELEMETRY = "1"
    $env:NUGET_PACKAGES = Join-Path $P9 "nuget\packages"
    $env:NUGET_HTTP_CACHE_PATH = Join-Path $P9 "nuget\http-cache"
    $env:NUGET_PLUGINS_CACHE_PATH = Join-Path $P9 "nuget\plugins-cache"
    New-Item -ItemType Directory -Force $env:PUB_CACHE, $env:APPDATA, $env:LOCALAPPDATA, $env:NUGET_PACKAGES, $env:NUGET_HTTP_CACHE_PATH, $env:NUGET_PLUGINS_CACHE_PATH | Out-Null
}

# Flags de swift (x64, runtime dinamico como P9\win\core.ps1). $Config: release o debug.
function Get-SwiftArgs([string]$Config = "release", [string]$Package = $Pkg) {
    return @("-c", $Config, "--arch", "x86_64", "--package-path", $Package,
             "--cache-path", (Join-Path $SpmDir "cache"),
             "--config-path", (Join-Path $SpmDir "config"),
             "--security-path", (Join-Path $SpmDir "security"))
}

# Imprime un paso y sale con su codigo (no deja que un fallo parezca verde).
function Stop-Step([int]$Code, [string]$Msg) {
    if ($Code -ne 0) { Write-Output "TF:FALLO $Msg (codigo $Code)" }
    exit $Code
}
