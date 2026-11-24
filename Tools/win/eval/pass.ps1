# Pase unico de validacion de ToneForge en un PC Windows x64 (local, sin SSH). Solo ASCII. PS 5.1 y 7.
# Uso (en la raiz del clon, tras extraer pc-bundle.zip):
#   powershell -NoProfile -ExecutionPolicy Bypass -File Tools\win\eval\pass.ps1 [-Skip build,tests,...] [-With directml] [-ProjectsSource <dir>]
# Partes en orden: preflight, build, tests, montage-full, montage-cancel, b2, b34-firstrun, b34-photos, b6, f3, directml (solo con -With directml).
# Salidas: Temp\win\pass\<parte>.out, Temp\win\pass\summary.txt, Temp\win\pass\f3-timing.txt. Nunca toca HeadRush ni camara: la app va con --audio/--camera simulated
#   (montage/b2/b34/b6: ver los lanzadores; b2/b34/montage solo pasan --audio simulated y no abren la pantalla de grabacion).
# Truco: <unidad del clon>\tf (C:\tf en la VM) es una union (junction) al clon, asi se reutilizan sin cambios Tools\win\remote\{build,install,test}.ps1 (las que usa build.sh en la VM).
param([string[]]$Skip = @(), [string[]]$With = @(), [string]$ProjectsSource = "", [string]$OrtDll = "")
# -OrtDll <ruta onnxruntime.dll> (o TF_ORT_DLL): ORT alternativa (p. ej. DirectML). Se exporta a todas las partes y se escribe en los .env de los lanzadores b2/b34/montage
#   (las tareas no heredan el entorno). f3 va siempre con la ORT por defecto (referencia CPU). -Skip acepta tambien montage-full y montage-cancel.
$Skip = @($Skip | ForEach-Object { $_ -split "," } | Where-Object { $_ }); $With = @($With | ForEach-Object { $_ -split "," } | Where-Object { $_ })   # -File entrega "a,b" como un solo texto
$ErrorActionPreference = "Continue"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$Out = Join-Path $Root "Temp\win\pass"; New-Item -ItemType Directory -Force $Out | Out-Null
$PSX = (Get-Process -Id $PID).Path
$PS51 = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$Remote = Join-Path $Root "Tools\win\remote"
# Unidad de trabajo = la del clon (o TF_DRIVE); la heredan Tools\win\remote y los lanzadores (C: si no se define).
$Drive = if ($env:TF_DRIVE) { $env:TF_DRIVE.TrimEnd('\') } else { Split-Path -Qualifier $Root }
$env:TF_DRIVE = $Drive; $env:TF_WEBVIEW2_DIR = "$Drive\tf-webview2"
$Junction = "$Drive\tf"
$Install = "$Drive\ToneForge\x64"; $QA = "$Drive\tf-qa"
$Rows = New-Object System.Collections.ArrayList
$Models = if (Test-Path (Join-Path $Root "Vendor\models-win")) { Join-Path $Root "Vendor\models-win" } elseif ($env:TF_MODELS_DIR) { $env:TF_MODELS_DIR } else { "$Drive\tf-models" }
$env:TF_MODELS_DIR = $Models
if (-not $OrtDll -and $env:TF_ORT_DLL) { $OrtDll = $env:TF_ORT_DLL }
if ($OrtDll) { $env:TF_ORT_DLL = $OrtDll } else { Remove-Item Env:\TF_ORT_DLL -ErrorAction SilentlyContinue }
$PassStart = Get-Date; $script:RowStart = $PassStart
$ProjSrc = if ($ProjectsSource) { $ProjectsSource } else { Join-Path $Root "Temp\qa-7c\evalB\projects" }

function Skipped($n) { return ($Skip -contains $n) }
# Cada fila lleva inicio, fin y duracion (las partes son secuenciales: el inicio es el fin de la fila anterior).
function Add-Row($n, $res, $file) {
    $end = Get-Date; $t = "{0:HH:mm:ss} -> {1:HH:mm:ss} ({2:N1} min)" -f $script:RowStart, $end, (($end - $script:RowStart).TotalMinutes); $script:RowStart = $end
    [void]$Rows.Add(("{0,-16} | {1,-26} | {2} | {3}" -f $n, $res, $t, $file)); Write-Host $Rows[$Rows.Count - 1]
}
function Tally($file) {
    $ok = 0; $bad = 0; $sk = 0
    if (Test-Path $file) { foreach ($l in (Get-Content $file -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        if ($l -match "eval\| OK\b") { $ok++ } elseif ($l -match "eval\| FAIL\b") { $bad++ } elseif ($l -match "eval\| SKIP\b") { $sk++ } } }
    return @($ok, $bad, $sk)
}
# Lanza un guion y cuenta sus lineas eval| OK/FAIL/SKIP. rc != 0 o TIMEOUT o 0 pruebas = FALLO/TIMEOUT.
function Run-Eval($name, $argv) {
    $f = Join-Path $Out "$name.out"
    Write-Host "== $name"
    & $PSX -NoProfile -ExecutionPolicy Bypass @argv *> $f
    $rc = $LASTEXITCODE
    foreach ($p in "ToneForge", "yt-dlp", "ffmpeg") { Get-Process -Name $p -ErrorAction SilentlyContinue | Stop-Process -Force }   # sin restos entre partes
    $t = Tally $f
    $txt = Get-Content $f -Raw -ErrorAction SilentlyContinue
    if ($txt -match "TIMEOUT") { Add-Row $name "TIMEOUT ($($t[0])/$($t[0] + $t[1]))" $f }
    elseif ($rc -ne 0 -or ($t[0] + $t[1]) -eq 0) { Add-Row $name "FALLO (rc $rc, $($t[0])/$($t[0] + $t[1]))" $f }
    else { $r = if ($t[1] -gt 0) { "FALLO " } else { "DONE " }; Add-Row $name ("$r$($t[0])/$($t[0] + $t[1]) (skip $($t[2]))") $f }
}
function Run-Remote($script, $argv, $file) {   # scripts remotos de Tools\win\remote (PowerShell 5.1)
    & $PS51 -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Remote $script) @argv *> $file
    return $LASTEXITCODE
}

# ---------------- preflight ----------------
function Preflight {
    $f = Join-Path $Out "preflight.out"; $bad = New-Object System.Collections.ArrayList
    function Need($cond, $msg) { if (-not $cond) { [void]$bad.Add($msg) } }
    Need ([bool](Get-Command swift -ErrorAction SilentlyContinue)) "swift no esta en el PATH. Instala el toolchain Swift para Windows: winget install --id Swift.Toolchain (y abre una consola nueva)"
    $vs = & "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" -products * -latest -property installationPath 2>$null
    Need ([bool]$vs) "faltan las VS Build Tools (C++ y Windows SDK). winget install --id Microsoft.VisualStudio.2022.BuildTools --override '--quiet --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended'"
    $wv = Join-Path $Root "Vendor\win\webview2\VERSION"; Need (Test-Path $wv) "falta Vendor\win\webview2 (esta en pc-bundle.zip: extraelo en la raiz del clon)"
    Need (Test-Path (Join-Path $Root "Vendor\win\ort\VERSION")) "falta Vendor\win\ort (pc-bundle.zip)"
    $hx = Join-Path $Root "Vendor\helpers-win\x64"
    foreach ($h in "yt-dlp.exe", "deno.exe", "ffmpeg.exe") { Need (Test-Path (Join-Path $hx $h)) "falta Vendor\helpers-win\x64\$h (pc-bundle.zip)" }
    foreach ($m in "bs_roformer\model.onnx", "bs_roformer\T1_mix_60-85s.wav", "pose\model.onnx") { Need (Test-Path (Join-Path $Models $m)) "falta $Models\$m (pc-bundle.zip: Vendor\models-win, o define TF_MODELS_DIR)" }
    Need ((Get-ChildItem -Directory $ProjSrc -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0) "no hay proyectos de prueba en $ProjSrc (pc-bundle.zip o -ProjectsSource <dir>; nunca reales)"
    # Union <unidad>\tf -> clon
    if (Test-Path $Junction) { $t = (Get-Item $Junction).Target; if (-not $t -or ((@($t)[0]).TrimEnd('\') -ne $Root.TrimEnd('\'))) { [void]$bad.Add("$Junction existe y no es una union a este clon: renombrala o borrala (cmd /c rmdir $Junction)") } }
    elseif ($bad.Count -eq 0) { & cmd /c mklink /J $Junction "$Root" | Out-Null }
    if ($bad.Count -gt 0) { $bad | ForEach-Object { "FALTA: $_" } | Out-File $f -Encoding utf8; Get-Content $f | Write-Host; Add-Row "preflight" "FALLO ($($bad.Count) faltas)" $f; return $false }
    "preflight ok; unidad=$Drive; union=$Junction; instalacion=$Install; qa=$QA; modelos=$Models; proyectos=$ProjSrc" | Out-File $f -Encoding utf8
    Add-Row "preflight" "DONE" $f; return $true
}
if (-not (Preflight)) { Set-Content (Join-Path $Out "summary.txt") $Rows; exit 3 }

# ---------------- build ----------------
if (-not (Skipped "build")) {
    $f = Join-Path $Out "build.out"; "" | Out-File $f
    # ORT y WebView2 en sus carpetas persistentes (las que esperan common.ps1 y el paquete WinApp)
    foreach ($d in @(@("ort", "$Drive\tf-ort"), @("webview2", "$Drive\tf-webview2"))) {
        $src = Join-Path $Root "Vendor\win\$($d[0])"
        if ((-not (Test-Path "$($d[1])\VERSION")) -or ((Get-Content "$($d[1])\VERSION") -ne (Get-Content "$src\VERSION"))) {
            Remove-Item -Recurse -Force $d[1] -ErrorAction SilentlyContinue; New-Item -ItemType Directory -Force $d[1] | Out-Null
            Copy-Item "$src\*" $d[1] -Recurse -Force
        }
    }
    $rc = Run-Remote "build.ps1" @("-Package", "WinApp", "-Arch", "x64") $f
    if ($rc -eq 0) { $rc = Run-Remote "build.ps1" @("-Package", "Packages/StemKit", "-Arch", "x64") ($f + ".stem") }
    if ($rc -eq 0) { $rc = Run-Remote "install.ps1" @("-Package", "WinApp", "-Product", "ToneForge", "-Arch", "x64") ($f + ".install") }
    # helpers de Windows junto al exe (yt-dlp, deno, ffmpeg)
    if ($rc -eq 0) { Copy-Item (Join-Path $Root "Vendor\helpers-win\x64\*") $Install -Force }
    Add-Row "build" $(if ($rc -eq 0) { "DONE" } else { "FALLO (rc $rc)" }) $f
}

# ---------------- tests (NTFS real) ----------------
if (-not (Skipped "tests")) {
    $cases = @(@("AppCore", "Packages/AppCore", "DeleteTake", ""), @("Store.DeleteTakeRetry", "Packages/Store", "DeleteTakeRetryTests", ""),
               @("Store.GuitarFingerprint", "Packages/Store", "GuitarFingerprintTests", ""), @("AppCore.FrameRelay", "Packages/AppCore", "FrameRelayTests", ""))
    foreach ($c in $cases) {
        $f = Join-Path $Out "tests-$($c[0]).out"
        $a = @("-Package", $c[1], "-Arch", "x64", "-Filter", $c[2], "-TimeoutSec", "900", "-IdleSec", "0")
        $rc = Run-Remote "test.ps1" $a $f
        $txt = Get-Content $f -Raw -ErrorAction SilentlyContinue
        $ex = [regex]::Matches($txt, "Executed (\d+) tests?, with (?:(\d+) tests? skipped and )?(\d+) failures?") | Select-Object -Last 1
        $res = if ($ex) { $n = [int]$ex.Groups[1].Value; $sk = if ($ex.Groups[2].Success) { [int]$ex.Groups[2].Value } else { 0 }; $fl = [int]$ex.Groups[3].Value; "$($n - $sk - $fl)/$n (skip $sk, fallos $fl)" } else { "sin totales" }
        $sha = [regex]::Match($txt, "SHA-256 de 92 MB[^\r\n]*")
        if ($sha.Success) { $res += " | " + $sha.Value }
        $state = if ($txt -match "TF:TIMEOUT") { "TIMEOUT" } elseif ($rc -eq 0 -and $ex) { "DONE" } else { "FALLO" }
        Add-Row ("tests " + $c[0]) "$state $res" $f
    }
}

# ---------------- montaje, b2, b34 ----------------
New-Item -ItemType Directory -Force $QA | Out-Null
if (-not (Test-Path "$QA\projects") -or -not (Get-ChildItem "$QA\projects" -ErrorAction SilentlyContinue)) {
    & robocopy $ProjSrc "$QA\projects" /E /XD .partial-guitars /XF .DS_Store /NFL /NDL /NJH /NJS /NP | Out-Null
}
$E = Join-Path $Root "Tools\win\eval"
if (-not ((Skipped "montage") -or (Skipped "montage-full"))) {
    Run-Eval "montage-full" @("-File", "$E\montage-launch.ps1", "-Mode", "full", "-Models", $Models, "-LimitMin", "45")
}
if (-not ((Skipped "montage") -or (Skipped "montage-cancel"))) {
    Run-Eval "montage-cancel" @("-File", "$E\montage-launch.ps1", "-Mode", "cancel", "-Models", $Models, "-LimitMin", "45")
}
if (-not (Skipped "b2")) { Run-Eval "b2" @("-File", "$E\b2-launch.ps1", "-LimitMin", "45") }
if (-not (Skipped "b34-firstrun")) { Run-Eval "b34-firstrun" @("-File", "$E\b34-launch.ps1", "-Mode", "firstrun", "-LimitMin", "10") }
if (-not (Skipped "b34-photos")) { Run-Eval "b34-photos" @("-File", "$E\b34-launch.ps1", "-Mode", "photos", "-LimitMin", "10") }
if (-not (Skipped "b6")) { Run-Eval "b6" @("-File", "$E\b6-launch.ps1") }

# ---------------- f3 y directml: tf-separate con TF_SEPARATE_TIMING=1 ----------------
function Run-Separate($name, $provider) {
    $f = Join-Path $Out "$name.out"; $o = Join-Path $Out "$name-stems"
    Remove-Item -Recurse -Force $o -ErrorAction SilentlyContinue
    if ($name -eq "f3") { Remove-Item Env:\TF_ORT_DLL -ErrorAction SilentlyContinue }   # f3 = referencia con la ORT por defecto
    $env:TF_SEPARATE_TIMING = "1"; if ($provider) { $env:TF_ONNX_PROVIDER = $provider } else { Remove-Item Env:\TF_ONNX_PROVIDER -ErrorAction SilentlyContinue }
    $mdl = Join-Path $Models "bs_roformer\model.onnx"; $wav = Join-Path $Models "bs_roformer\T1_mix_60-85s.wav"   # 25 s de audio
    $p = Start-Process -FilePath (Join-Path $Install "tf-separate.exe") -ArgumentList @("--model", "`"$mdl`"", "--input", "`"$wav`"", "--out", "`"$o`"") -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$f.stdout" -RedirectStandardError $f
    Remove-Item Env:\TF_SEPARATE_TIMING, Env:\TF_ONNX_PROVIDER -ErrorAction SilentlyContinue
    if ($OrtDll) { $env:TF_ORT_DLL = $OrtDll }
    $all = (Get-Content $f -ErrorAction SilentlyContinue) + (Get-Content "$f.stdout" -ErrorAction SilentlyContinue)
    $secs = $null; foreach ($l in $all) { if ($l -match '"stage":"done","seconds":([0-9.]+)') { $secs = [double]$Matches[1] } }
    $all | Out-File (Join-Path $Out "$name-timing.txt") -Encoding utf8
    if ($p.ExitCode -eq 0 -and $secs) { Add-Row $name ("DONE {0:N1} s para 25 s de audio = {1:N0} s/min" -f $secs, ($secs / 25 * 60)) $f } else { Add-Row $name "FALLO (rc $($p.ExitCode))" $f }
}
if (-not (Skipped "f3")) { Run-Separate "f3" ""; Copy-Item (Join-Path $Out "f3-timing.txt") (Join-Path $Root "Temp\win\f3-timing.txt") -ErrorAction SilentlyContinue }
if ($With -contains "directml") {
    if (-not (Skipped "directml-main")) { Run-Separate "directml-main" "directml" }
    $f = Join-Path $Out "directml-guitars.out"
    # Las variables van por el entorno (lo hereda test.ps1): un -SetEnv con ";" lo parte PS 5.1 en -File y el resto caia en -Config.
    $env:TF_MODEL_TESTS = "1"; $env:TF_MODELS_DIR = $Models; $env:TF_ONNX_PROVIDER = "directml"; $env:TF_SEPARATE_TIMING = "1"
    $rc = Run-Remote "test.ps1" @("-Package", "Packages/StemKit", "-Arch", "x64", "-Filter", "LeadSeparatorHeavyTests|DirectMLParityTests", "-TimeoutSec", "1800", "-IdleSec", "0") $f
    Remove-Item Env:\TF_MODEL_TESTS, Env:\TF_ONNX_PROVIDER, Env:\TF_SEPARATE_TIMING -ErrorAction SilentlyContinue
    Add-Row "directml-guitars" $(if ($rc -eq 0) { "DONE (tiempos en el .out)" } else { "FALLO (rc $rc)" }) $f
}

# ---------------- evidencia de la ORT usada ----------------
$ev = Join-Path $Out "ort-evidence.txt"
"TF_ORT_DLL=$OrtDll" | Out-File $ev -Encoding utf8
if ($OrtDll -and (Test-Path $OrtDll)) { $vi = (Get-Item $OrtDll).VersionInfo; "onnxruntime.dll FileVersion=$($vi.FileVersion) ProductVersion=$($vi.ProductVersion)" | Out-File $ev -Append -Encoding utf8 }
Get-ChildItem $QA -Recurse -Filter "*.log" -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $PassStart } | ForEach-Object {
    $n = $_.Name; Select-String -Path $_.FullName -Pattern "onnx\|" -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object { "$n : " + $_.Line } } | Out-File $ev -Append -Encoding utf8
foreach ($pf in "directml-main.out", "directml-main.out.stdout") { $pp = Join-Path $Out $pf; if (Test-Path $pp) { Select-String -Path $pp -Pattern "provider|directml|onnx" -ErrorAction SilentlyContinue | Select-Object -First 5 | ForEach-Object { "$pf : " + $_.Line } | Out-File $ev -Append -Encoding utf8 } }

# ---------------- resumen ----------------
$hdr = "{0,-16} | {1,-26} | {2} | {3}" -f "parte", "resultado", "inicio -> fin (duracion)", "fichero"
$txt = @($hdr) + $Rows
$txt += ("pase: {0:HH:mm:ss} -> {1:HH:mm:ss}; ORT: {2}" -f $PassStart, (Get-Date), $(if ($OrtDll) { $OrtDll } else { "por defecto" }))
$txt | Out-File (Join-Path $Out "summary.txt") -Encoding utf8
Write-Host ""; $txt | ForEach-Object { Write-Host $_ }
Write-Host "Resumen: $(Join-Path $Out 'summary.txt')"
