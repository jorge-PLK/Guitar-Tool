# B2, parte externa (se llama por ssh desde Temp/win/eval/b2-run.sh). Solo ASCII.
# Copia temas de C:\tf-qa\projects a carpetas NUEVAS de C:\tf-qa\b2 (nunca toca los proyectos reales) y lanza dos veces la app
# en la sesion interactiva de tf (schtasks /IT): fase a (mover, apuntar, trabajo en cola) y fase b (reinicio sin --projects-folder).
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File C:\tf-qa\b2\b2-launch.ps1 [-LimitMin 45] [-NoPickHook]
# Gancho TF_TEST_PICK_FOLDER (AppCore): por defecto la fase a lo lleva con la carpeta de "mover" (P1), asi el primer cambio de carpeta usa el RPC
#   host.chooseFolder real de la app. Una variable de entorno da una sola ruta: "apuntar" (P2) y "trabajo en cola" (P3) siguen con el interceptor del JS.
#   -NoPickHook: sin la variable; todo el selector va por el interceptor del JS (camino anterior).
param(
    [string]$Work = "",
    [string]$Source = "",
    [string]$First = "El roce*",
    [int]$LimitMin = 45,
    [switch]$NoPickHook
)
$ErrorActionPreference = "Continue"
$PSX = (Get-Process -Id $PID).Path   # el mismo PowerShell (5.1 o 7) para los guiones internos
$TfDrive = if ($env:TF_DRIVE) { $env:TF_DRIVE.TrimEnd('\') } else { "C:" }   # pass.ps1 la pone a la unidad del clon
if (-not $Work) { $Work = "$TfDrive\tf-qa\b2" }; if (-not $Source) { $Source = "$TfDrive\tf-qa\projects" }

$Exe = if ($env:TF_EXE) { $env:TF_EXE } else { "$TfDrive/ToneForge/x64/ToneForge.exe" }   # TF_EXE: instalacion de prueba aparte
if (-not (Test-Path $Exe)) { Write-Output "B2 SINAPP: falta $Exe (build.sh --no-run)"; exit 3 }

$all = @(Get-ChildItem -Directory $Source -ErrorAction SilentlyContinue | Where-Object { Test-Path (Join-Path $_.FullName "project.json") })
$one = $all | Where-Object { $_.Name -like $First } | Select-Object -First 1
if (-not $one) { Write-Output "B2 SINTEMA: no hay '$First' en $Source"; exit 3 }
$two = $all | Where-Object { $_.FullName -ne $one.FullName } | Select-Object -First 1
if (-not $two) { $two = $one }

New-Item -ItemType Directory -Force $Work | Out-Null
$p0 = Join-Path $Work "proj-old"; $p1 = Join-Path $Work "proj-moved"; $p2 = Join-Path $Work "proj-pointed"; $p3 = Join-Path $Work "proj-wip"
$support = Join-Path $Work "support"
Remove-Item -Recurse -Force $p0, $p1, $p2, $p3, $support -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $p0, $p2, $support | Out-Null   # p1 y p3 NO existen: la app los crea
$inSet = @($one) + @($all | Where-Object { $_.FullName -ne $one.FullName } | Select-Object -First 1)
foreach ($t in ($inSet | Select-Object -Unique)) {
    & robocopy $t.FullName (Join-Path $p0 $t.Name) /E /XD .partial-guitars /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { Write-Output "B2 ROBOCOPY fallo ($LASTEXITCODE) en $($t.Name)"; exit 3 }
}
& robocopy $two.FullName (Join-Path $p2 $two.Name) /E /XD .partial-guitars /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { Write-Output "B2 ROBOCOPY fallo ($LASTEXITCODE) en P2"; exit 3 }
$n0 = @(Get-ChildItem $p0 -Recurse -Force -File).Count
Write-Output ("B2 copias: P0 {0} ({1} temas, {2} ficheros), P2 {3} (1 tema: {4})" -f $p0, @(Get-ChildItem -Directory $p0).Count, $n0, $p2, $two.Name)

$hook = if ($NoPickHook) { "" } else { $p1 }   # ruta que devolvera el selector de la fase a (gancho TF_TEST_PICK_FOLDER)
function Lit([string]$s) { return $s.Replace('\', '\\') }
$body = [IO.File]::ReadAllText((Join-Path $PSScriptRoot "b2-relocate.js"), [Text.Encoding]::UTF8)
$utf8 = New-Object Text.UTF8Encoding($false)
function Prefix([string]$ph) {
    $h = if ($ph -eq "a") { $hook } else { "" }
    return "globalThis.B2_PHASE = '$ph'; globalThis.B2_PICK_HOOK = '$(Lit $h)'; globalThis.B2_P0 = '$(Lit $p0)'; globalThis.B2_P1 = '$(Lit $p1)'; globalThis.B2_P2 = '$(Lit $p2)'; globalThis.B2_P3 = '$(Lit $p3)'; globalThis.B2_P2_COUNT = 1;`n"
}
$common = "--support-dir `"$support`" --audio simulated --camera simulated --window 1440x900"
$phases = @(
    @{ id = "a"; limit = $LimitMin; args = "--projects-folder `"$p0`" $common --screen library --eval-delay 6" },
    @{ id = "b"; limit = 5;         args = "$common --screen settings-library --eval-delay 6" }
)
foreach ($ph in $phases) {
    $id = $ph.id
    $evalFile = Join-Path $Work "b2-relocate-$id.js"
    [IO.File]::WriteAllText($evalFile, (Prefix $id) + $body, $utf8)
    [IO.File]::WriteAllText((Join-Path $Work "b2-$id.args"), ($ph.args + " --eval-file `"$evalFile`""))
    $envLine = "TF_X=1"
    if ($env:TF_ORT_DLL) { $envLine += ";TF_ORT_DLL=$($env:TF_ORT_DLL)" }   # la tarea no hereda el entorno de pass.ps1
    if ($id -eq "a" -and $hook) { $envLine += ";TF_TEST_PICK_FOLDER=$hook" }
    [IO.File]::WriteAllText((Join-Path $Work "b2-$id.env"), $envLine)
    $done = Join-Path $Work "b2-$id.done"
    Remove-Item -Force $done -ErrorAction SilentlyContinue
    $task = "tf-b2-$id"
    & $PSX -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "b2-task.ps1") -Phase $id -Work $Work -LimitMin $ph.limit | Out-Null
    $limit = (Get-Date).AddMinutes($ph.limit + 2)
    while (-not (Test-Path $done) -and (Get-Date) -lt $limit) { Start-Sleep -Seconds 2 }
    if (Test-Path $done) { Write-Output ("B2 FIN fase $id codigo " + ((Get-Content $done | Select-Object -First 1))) } else { Write-Output "B2 TIMEOUT del lanzador en la fase $id" }
    Get-Content (Join-Path $Work "b2-$id.launch.txt") -ErrorAction SilentlyContinue | ForEach-Object { Write-Output "B2 lanzado $id`: $_" }
    $log = Join-Path $Work "app-$id.log"
    if (Test-Path $log) { Get-Content $log -Encoding UTF8 | Select-String -Pattern "eval\|" | ForEach-Object { Write-Output $_.Line } }
    if ($id -eq "a" -and -not (Test-Path $done)) { break }
    Start-Sleep -Seconds 3
}
exit 0
