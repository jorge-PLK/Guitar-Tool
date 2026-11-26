# Clon propio de la rama de la 7f en <P9>\f7 (el checkout de la 7c, D:\Personal\Guitar-Tool, no se toca).
param([string]$Branch = "fase-7f")
. "$PSScriptRoot\common.ps1"
if (-not (Test-Path (Join-Path $Repo ".git"))) {
    & git clone --no-checkout -q $RemoteUrl $Repo 2>&1 | ForEach-Object { "$_" }
    if ($LASTEXITCODE -ne 0) { Stop-Step 1 "git clone" }
}
Set-Location $Repo
& git fetch -q origin $Branch 2>&1 | ForEach-Object { "$_" }
if ($LASTEXITCODE -ne 0) { Stop-Step 1 "git fetch" }
& git checkout -q -f -B $Branch "origin/$Branch" 2>&1 | ForEach-Object { "$_" }
if ($LASTEXITCODE -ne 0) { Stop-Step 1 "git checkout" }
New-Item -ItemType Directory -Force $Shots | Out-Null
# Helpers (yt-dlp, deno, ffmpeg) que exige FlutterApp\windows\CMakeLists.txt: Vendor/ no esta en git; se copian (solo lectura)
# del paquete de la 7c, D:\tf\Vendor\helpers-win\x64.
$helpers = Join-Path $Repo "Vendor\helpers\win-x64"
if (-not (Test-Path (Join-Path $helpers "yt-dlp.exe"))) {
    $from = "D:\tf\Vendor\helpers-win\x64"
    if (-not (Test-Path (Join-Path $from "yt-dlp.exe"))) { Stop-Step 1 "faltan los helpers: $from" }
    New-Item -ItemType Directory -Force $helpers | Out-Null
    Copy-Item (Join-Path $from "*") $helpers -Force
    Write-Output "TF:helpers copiados de $from"
}
$head = (& git log --oneline -1) -join ""
Write-Output "TF:HEAD $Branch $head"
Write-Output "TF:CHECKOUT-7C $((& git -C (Resolve-Path (Join-Path $P9 '..\..')).Path branch --show-current) -join '')"
exit 0
