# Lanza la app en la sesion interactiva de Jorge (tarea programada /IT) y espera a shot-task.ps1.
# -ArgsB64: argumentos extra de la app en base64 (UTF-8). Deja en <repo>\Temp\flutter: desktop.png, app-snapshot.png, app.out/.err, shot.done.
param([string]$ArgsB64 = "")
. "$PSScriptRoot\common.ps1"
$user = $env:USERNAME
$interactive = $false
foreach ($p in (Get-CimInstance Win32_Process -Filter "Name='explorer.exe'")) {
    $owner = Invoke-CimMethod -InputObject $p -MethodName GetOwner
    if ($owner.User -eq $user -and $p.SessionId -ne 0) { $interactive = $true }
}
if (-not $interactive) { Write-Output "TF:SINSESION $user no tiene sesion grafica (conecta Moonlight)"; exit 3 }
if (-not (Test-Path $AppExe)) { Stop-Step 1 "no hay .exe; ejecuta antes el paso app" }

New-Item -ItemType Directory -Force $Shots | Out-Null
$done = Join-Path $Shots "shot.done"
Remove-Item -Force $done, (Join-Path $Shots "desktop.png"), (Join-Path $Shots "app-snapshot.png"), (Join-Path $Shots "app.out"), (Join-Path $Shots "app.err") -ErrorAction SilentlyContinue
$extra = ""
if ($ArgsB64 -ne "") { $extra = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ArgsB64)) }
[IO.File]::WriteAllText((Join-Path $Shots "shot.args"), $extra)

$task = "tf-flutter-shot"
$tr = "powershell -NoProfile -ExecutionPolicy Bypass -File $PSScriptRoot\shot-task.ps1"
& schtasks /Create /TN $task /TR $tr /SC ONCE /ST 23:59 /RU $user /IT /F | Out-Null
& schtasks /Run /TN $task | Out-Null
$limit = (Get-Date).AddSeconds(120)
while (-not (Test-Path $done) -and (Get-Date) -lt $limit) { Start-Sleep -Milliseconds 500 }
& schtasks /Delete /TN $task /F | Out-Null
if (-not (Test-Path $done)) { Write-Output "TF:SHOT TIMEOUT"; exit 1 }
$rc = [int](Get-Content $done | Select-Object -First 1)
Write-Output "TF:SHOT app rc=$rc"
foreach ($f in @("app.out", "app.err")) {
    $p = Join-Path $Shots $f
    if (Test-Path $p) { Get-Content $p -TotalCount 40 | ForEach-Object { Write-Output "  [$f] $_" } }
}
$ok = (Test-Path (Join-Path $Shots "app-snapshot.png")) -and (Test-Path (Join-Path $Shots "desktop.png"))
if ($rc -ne 0 -or -not $ok) { Write-Output "TF:SHOT sin captura completa o con codigo de salida distinto de 0"; exit 1 }
exit 0
