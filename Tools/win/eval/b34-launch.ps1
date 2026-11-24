# B3/B4, parte externa (por ssh desde b34-run.sh). Solo ASCII. Todo en C:\tf-qa\b34 (copia de proyectos y soporte NUEVOS, nunca los reales).
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File C:\tf-qa\b34\b34-launch.ps1 -Mode firstrun|photos [-LimitMin 10] [-NoPickHook]
# firstrun: por defecto el 1.er lanzamiento lleva TF_TEST_PICK_FOLDER=<fr-projects> (gancho de AppCore: host.pickProjectsFolder devuelve la ruta sin abrir el
#   dialogo; el resto del camino es el real) y no se maneja UI Automation. -NoPickHook: sin variable, el selector nativo se rellena con UIA (b34-task.ps1 -DialogPath).
param([string]$Mode = "photos", [string]$Work = "", [string]$Source = "", [int]$LimitMin = 10, [switch]$NoPickHook)
$ErrorActionPreference = "Continue"
$TfDrive = if ($env:TF_DRIVE) { $env:TF_DRIVE.TrimEnd('\') } else { "C:" }   # pass.ps1 la pone a la unidad del clon
if (-not $Work) { $Work = "$TfDrive\tf-qa\b34" }; if (-not $Source) { $Source = "$TfDrive\tf-qa\projects" }
$PSX = (Get-Process -Id $PID).Path   # el mismo PowerShell (5.1 o 7) para los guiones internos
$script:ok = 0; $script:bad = 0; $script:skip = 0
function Chk($n, $c, $d) { if ($c) { $script:ok++; Write-Output "eval| OK $n $d" } else { $script:bad++; Write-Output "eval| FAIL $n $d" } }
$Exe = if ($env:TF_EXE) { $env:TF_EXE } else { "$TfDrive/ToneForge/x64/ToneForge.exe" }   # TF_EXE: instalacion de prueba aparte
if (-not (Test-Path $Exe)) { Write-Output "B34 SINAPP: falta $Exe (build.sh --no-run)"; exit 3 }
New-Item -ItemType Directory -Force $Work | Out-Null
$OFFLINE = "HTTPS_PROXY=http://127.0.0.1:9;https_proxy=http://127.0.0.1:9;SPOTIFY_CLIENT_ID=invalid;SPOTIFY_CLIENT_SECRET=invalid"

# Un lanzamiento: escribe args/env/guion, lanza b34-task.ps1 con schtasks /IT, espera, imprime las lineas eval|.
function Launch($name, $argsLine, $envLine, $prelude, $dialogPath) {
    $body = [IO.File]::ReadAllText((Join-Path $PSScriptRoot "b34-firstrun.js"), [Text.Encoding]::UTF8)
    $evalFile = Join-Path $Work "$name.js"
    [IO.File]::WriteAllText($evalFile, "$prelude`n$body", (New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText((Join-Path $Work "$name.args"), "$argsLine --audio simulated --camera simulated --screen library --window 1440x900 --eval-file `"$evalFile`" --eval-delay 6")
    if ($env:TF_ORT_DLL) { $envLine += ";TF_ORT_DLL=$($env:TF_ORT_DLL)" }   # la tarea no hereda el entorno de pass.ps1
    [IO.File]::WriteAllText((Join-Path $Work "$name.env"), $envLine)
    $done = Join-Path $Work "$name.done"; Remove-Item -Force $done -ErrorAction SilentlyContinue
    $ta = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $PSScriptRoot "b34-task.ps1"), "-Name", $name, "-Work", $Work, "-LimitMin", "$LimitMin")
    if ($dialogPath) { $ta += @("-DialogPath", $dialogPath) }
    & $PSX @ta | Out-Null
    $limit = (Get-Date).AddMinutes($LimitMin + 2)
    while (-not (Test-Path $done) -and (Get-Date) -lt $limit) { Start-Sleep -Seconds 2 }
    $code = if (Test-Path $done) { (Get-Content $done | Select-Object -First 1) } else { "TIMEOUT" }
    Write-Host "B34 lanzamiento $name fin codigo $code (0 ok, 124 tope, 2 la app murio)"
    $dt = Join-Path $Work "$name.dialog.txt"; if (Test-Path $dt) { Get-Content $dt | ForEach-Object { Write-Host "dialog| $_" } }
    $lines = @(); if (Test-Path (Join-Path $Work "$name.log")) { $lines = Get-Content (Join-Path $Work "$name.log") -Encoding UTF8 | Select-String -Pattern "eval\|" | ForEach-Object { $_.Line } }
    $lines | ForEach-Object { Write-Host $_ }
    $d = $lines | Where-Object { $_ -match "DONE b34part \S+ (\d+)/(\d+) \(skip (\d+)\)" } | Select-Object -Last 1
    if ($d -and $d -match "DONE b34part \S+ (\d+)/(\d+) \(skip (\d+)\)") { $script:ok += [int]$Matches[1]; $script:bad += ([int]$Matches[2] - [int]$Matches[1]); $script:skip += [int]$Matches[3] }
    else { $script:bad++; Write-Host "eval| FAIL $name sin linea DONE b34part" }
    return $lines
}

if ($Mode -eq "firstrun") {
    $sup = Join-Path $Work "fr-support"; $chosen = Join-Path $Work "fr-projects"
    Remove-Item -Recurse -Force $sup, $chosen -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force $sup, $chosen | Out-Null
    [IO.File]::WriteAllText((Join-Path $chosen "b34-probe.txt"), "b34")
    $music = Join-Path $env:USERPROFILE "Music\ToneForge"; $musicBefore = Test-Path $music   # la propuesta del selector se crea aqui
    $pick = if ($NoPickHook) { "uia" } else { "hook" }
    $pre = "globalThis.B34_MODE='firstrun'; globalThis.B34_PICK='$pick'; globalThis.B34_CHOSEN='$($chosen.Replace('\','\\'))'; globalThis.B34_PROBE_TEXT='b34';"
    $a = "--support-dir `"$sup`""   # SIN --projects-folder: es lo que fuerza el primer arranque
    Chk "fr.soporte-vacio" ((Get-ChildItem $sup -Force | Measure-Object).Count -eq 0) "soporte nuevo $sup"
    $env1 = if ($NoPickHook) { "TF_NONE=1" } else { "TF_NONE=1;TF_TEST_PICK_FOLDER=$chosen" }   # solo el 1.er lanzamiento: el 2.o no debe necesitar selector
    $dlg1 = if ($NoPickHook) { $chosen } else { "" }
    Launch "fr1" $a $env1 ($pre + "globalThis.B34_LAUNCH='1'; globalThis.B34_DIALOG='ui';") $dlg1 | Out-Null
    $pf = Join-Path $sup "profile.json"
    Chk "fr.perfil-escrito" (Test-Path $pf) $pf
    $hash1 = if (Test-Path $pf) { (Get-FileHash $pf).Hash } else { "" }
    if (Test-Path $pf) { $j = Get-Content -Raw $pf | ConvertFrom-Json; Chk "fr.perfil-carpeta" ([string]$j.projectsFolder -match [regex]::Escape("fr-projects")) "projectsFolder=$($j.projectsFolder)" }
    Launch "fr2" $a "TF_NONE=1" ($pre + "globalThis.B34_LAUNCH='2'; globalThis.B34_DIALOG='none';") "" | Out-Null
    $hash2 = if (Test-Path $pf) { (Get-FileHash $pf).Hash } else { "" }
    Chk "fr.perfil-intacto-tras-2o-arranque" ($hash1 -ne "" -and $hash1 -eq $hash2) "hash $hash1 / $hash2"
    Write-Output "disk| propuesta Music\ToneForge: existia antes=$musicBefore, existe ahora=$(Test-Path $music)"
    if (-not $musicBefore -and (Test-Path $music) -and -not (Get-ChildItem $music -Force)) { Remove-Item $music -Force; Write-Output "disk| propuesta vacia creada por la prueba: borrada" }
} else {
    $src = Get-ChildItem -Directory $Source -ErrorAction SilentlyContinue
    if (-not $src) { Write-Output "B34 SINTEMA: no hay proyectos en $Source"; exit 3 }
    $proj = Join-Path $Work "projects"; $sup = Join-Path $Work "ph-support"; $supOff = Join-Path $Work "ph-support-off"
    Remove-Item -Recurse -Force $proj, $sup, $supOff -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force $proj, $sup, $supOff | Out-Null
    foreach ($s in $src) { & robocopy $s.FullName (Join-Path $proj $s.Name) /E /XD .partial-guitars /NFL /NDL /NJH /NJS /NP | Out-Null }
    # Red y credenciales (nunca se imprimen los valores)
    $envf = Join-Path $env:LOCALAPPDATA "ToneForge\.env"
    $hasId = (Test-Path $envf) -and ((Get-Content $envf) -match "^\s*SPOTIFY_CLIENT_ID\s*=\s*\S")
    Write-Output "creds| $envf existe=$(Test-Path $envf) SPOTIFY_CLIENT_ID=$([bool]$hasId) (entorno: $([bool]$env:SPOTIFY_CLIENT_ID))"
    foreach ($h in "api.spotify.com", "accounts.spotify.com") {
        $net = $false; try { $c = New-Object Net.Sockets.TcpClient; $net = $c.ConnectAsync($h, 443).Wait(4000); $c.Close() } catch {}
        Write-Output "net| $h:443 alcanzable=$net"
    }
    function Snap($dir) { $r = @{}; Get-ChildItem (Join-Path $dir "artists") -ErrorAction SilentlyContinue | ForEach-Object { $r[$_.Name] = "$($_.Length)|$($_.LastWriteTimeUtc.Ticks)" }; return $r }
    function Origin($stems, $before, $after, $tag) {
        foreach ($k in $stems.Keys) {
            $s = $stems[$k]; $img = "$s.img"; $miss = "$s.miss"
            $o = if ($before.ContainsKey($img) -and $after.ContainsKey($img)) { if ($before[$img] -eq $after[$img]) { "cache (intacta)" } else { "cache REESCRITA" } }
                 elseif ($after.ContainsKey($img)) { "red (Spotify) -> escrita en cache" } elseif ($after.ContainsKey($miss)) { "sin foto: Spotify no lo conoce (.miss)" } else { "sin foto: sin red/credenciales/error (nada escrito)" }
            $bytes = if ($after.ContainsKey($img)) { $after[$img].Split("|")[0] } else { 0 }
            Write-Output "origen| $tag $k stem=$s origen=$o bytes=$bytes"
        }
    }
    $pre = "globalThis.B34_MODE='photos';"; $a = "--projects-folder `"$proj`" --support-dir `"$sup`""
    $b0 = Snap $sup
    $l1 = Launch "ph-cold" $a "TF_NONE=1" ($pre + "globalThis.B34_LAUNCH='cold';") ""
    $m = ($l1 | Where-Object { $_ -match "INFO stems (\{.*\})" } | Select-Object -First 1)
    $stems = @{}; if ($m -and $m -match "INFO stems (\{.*\})") { (ConvertFrom-Json $Matches[1]).PSObject.Properties | ForEach-Object { $stems[$_.Name] = $_.Value } }
    Chk "ph.stems-del-guion" ($stems.Count -gt 0) "$($stems.Count) artistas"
    $b1 = Snap $sup; Origin $stems $b0 $b1 "cold"
    # Siembra: PNG 1x1 en artists\<stem>.img para los artistas sin foto (para probar la cache sin depender de la red)
    $png = [Convert]::FromBase64String("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")
    New-Item -ItemType Directory -Force (Join-Path $sup "artists") | Out-Null
    foreach ($k in $stems.Keys) { $p = Join-Path $sup "artists\$($stems[$k]).img"; if (-not (Test-Path $p)) { [IO.File]::WriteAllBytes($p, $png); Write-Output "disk| sembrado $k ($($png.Length) B)" } }
    $b2 = Snap $sup
    $exp = "[" + (($stems.Values | ForEach-Object { "'$_'" }) -join ",") + "]"
    Launch "ph-warm" $a $OFFLINE ($pre + "globalThis.B34_LAUNCH='warm'; globalThis.B34_EXPECT={photo:$exp};") "" | Out-Null
    $b3 = Snap $sup; Origin $stems $b2 $b3 "warm"
    $changed = @($b2.Keys | Where-Object { $b3[$_] -ne $b2[$_] }); $added = @($b3.Keys | Where-Object { -not $b2.ContainsKey($_) })
    Chk "ph.warm.cache-reutilizada-sin-peticion" ($changed.Count -eq 0 -and $added.Count -eq 0) "ficheros cambiados=$($changed.Count) nuevos=$($added.Count) (sin red ni credenciales: una peticion nueva no habria podido escribir)"
    $a2 = "--projects-folder `"$proj`" --support-dir `"$supOff`""
    Launch "ph-offline" $a2 $OFFLINE ($pre + "globalThis.B34_LAUNCH='offline'; globalThis.B34_EXPECT={photo:[]};") "" | Out-Null
    $bo = Snap $supOff; Origin $stems @{} $bo "offline"
    Chk "ph.offline.nada-escrito" (-not ($bo.Keys | Where-Object { $_ -like "*.img" })) "ficheros en artists: $($bo.Count)"
}
Write-Output "DONE b34 $($script:ok)/$($script:ok + $script:bad) (skip $($script:skip))"
exit 0
