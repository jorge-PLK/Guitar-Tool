# Montaje-export, parte externa (se llama por ssh desde Temp/win/eval/montage-run.sh). Solo ASCII.
# Copia los temas de C:\tf-qa\projects a una carpeta NUEVA (nunca toca los proyectos reales; sin video\ ni .partial-guitars),
# prepara el guion con el modo, lanza montage-task.ps1 en la sesion interactiva de tf (schtasks /IT) y espera.
# Imprime las lineas "eval|" y el estado del disco (video\ de cada tema copiado y restos parciales).
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File C:\tf-qa\montage\montage-launch.ps1 -Mode full|cancel [-LimitMin 45]
param(
    [string]$Mode = "full",
    [string]$Work = "C:\tf-qa\montage",
    [string]$Source = "C:\tf-qa\projects",
    [string]$Match = "*",
    [string]$Models = "C:\tf-models",
    [int]$LimitMin = 45
)
$ErrorActionPreference = "Continue"
$PSX = (Get-Process -Id $PID).Path   # el mismo PowerShell (5.1 o 7) para los guiones internos
if ($Mode -ne "full" -and $Mode -ne "cancel") { Write-Output "MONTAGE modo desconocido: $Mode"; exit 3 }


$srcs = @(Get-ChildItem -Directory $Source -ErrorAction SilentlyContinue | Where-Object { $_.Name -like $Match })
if ($srcs.Count -eq 0) { Write-Output "MONTAGE SINTEMA: no hay '$Match' en $Source"; exit 3 }
if (-not (Test-Path "C:\ToneForge\x64\ToneForge.exe")) { Write-Output "MONTAGE SINAPP: falta C:\ToneForge\x64\ToneForge.exe (build.sh --no-run)"; exit 3 }
if (-not (Test-Path (Join-Path $Models "pose\model.onnx"))) { Write-Output "MONTAGE AVISO: falta $Models\pose\model.onnx (el analisis de encuadre puede no terminar)" }

New-Item -ItemType Directory -Force $Work | Out-Null
$projects = Join-Path $Work "projects-$Mode"
$support = Join-Path $Work "support-$Mode"
Remove-Item -Recurse -Force $projects, $support -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $projects, $support | Out-Null
$dsts = @()
foreach ($s in $srcs) {
    $dst = Join-Path $projects $s.Name
    # /XD video: los montajes anteriores (cientos de MB) no se copian: el destino de la exportacion queda vacio.
    & robocopy $s.FullName $dst /E /XD .partial-guitars video /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { Write-Output "MONTAGE ROBOCOPY fallo ($LASTEXITCODE) en $($s.Name)"; exit 3 }
    $dsts += $dst
}
Write-Output "MONTAGE copia: $($dsts.Count) tema(s) en $projects; modo $Mode"

# Guion con el modo antepuesto (el evaluador lo ejecuta como cuerpo de funcion async).
$body = [IO.File]::ReadAllText((Join-Path $PSScriptRoot "montage-export.js"), [Text.Encoding]::UTF8)
$evalFile = Join-Path $Work "montage-export-$Mode.js"
[IO.File]::WriteAllText($evalFile, "globalThis.MONTAGE_MODE = '$Mode';`n" + $body, (New-Object Text.UTF8Encoding($false)))

# Argumentos y entorno por fichero (schtasks /TR admite 261 caracteres).
# --audio simulated: sin sesion WASAPI. --support-dir nuevo: perfil y Models aislados. TF_MODELS_DIR: pose (encuadre) sin descargar.
$args1 = "--projects-folder `"$projects`" --support-dir `"$support`" --audio simulated --camera simulated --window 1440x900 --eval-file `"$evalFile`" --eval-delay 6"
[IO.File]::WriteAllText((Join-Path $Work "montage-$Mode.args"), $args1)
[IO.File]::WriteAllText((Join-Path $Work "montage-$Mode.env"), "TF_MODELS_DIR=$Models")
$done = Join-Path $Work "montage-$Mode.done"
Remove-Item -Force $done -ErrorAction SilentlyContinue

$task = "tf-montage-$Mode"
& $PSX -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "montage-task.ps1") -Mode $Mode -Work $Work -LimitMin $LimitMin | Out-Null
$limit = (Get-Date).AddMinutes($LimitMin + 2)
while (-not (Test-Path $done) -and (Get-Date) -lt $limit) { Start-Sleep -Seconds 2 }

if (Test-Path $done) { Write-Output ("MONTAGE FIN codigo " + ((Get-Content $done | Select-Object -First 1))) } else { Write-Output "MONTAGE TIMEOUT del lanzador" }
Get-Content (Join-Path $Work "montage-$Mode.launch.txt") -ErrorAction SilentlyContinue | ForEach-Object { Write-Output "MONTAGE lanzado: $_" }
Get-Content (Join-Path $Work "montage-$Mode.temp.txt") -ErrorAction SilentlyContinue | ForEach-Object { Write-Output "temp| $_" }
# Log de la app: solo lo que importa (el resto se trae por scp).
$log = Join-Path $Work "app-$Mode.log"
if (Test-Path $log) { Get-Content $log -Encoding UTF8 | Select-String -Pattern "eval\|" | ForEach-Object { Write-Output $_.Line } }
# Disco: video\ de cada tema copiado (ficheros finales, parciales, WAV de pistas) y restos parciales en cualquier sitio.
foreach ($dst in $dsts) {
    $v = Join-Path $dst "video"
    Write-Output ("disk| " + (Split-Path $dst -Leaf) + "\video:")
    Get-ChildItem $v -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object { if ($_.PSIsContainer) { Write-Output ("disk|   [carpeta] {0}" -f $_.FullName.Substring($dst.Length)) } else { Write-Output ("disk|   {0} {1} bytes {2}" -f $_.FullName.Substring($dst.Length), $_.Length, $_.LastWriteTime.ToString("HH:mm:ss")) } }
    $partials = @(Get-ChildItem $dst -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*partial*" })
    Write-Output ("disk| restos parciales en el tema: " + $partials.Count)
    $partials | ForEach-Object { Write-Output ("disk|   " + $_.FullName) }
}
exit 0
