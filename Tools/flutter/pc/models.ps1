# PC-3: tests con inferencia real (TF_MODEL_TESTS=1) de StemKit, StudyKit y TabKit sobre el clon f7, de uno en uno, con tope
# de tiempo por test. Una pasada con ORT CPU y otra con DirectML. Referencia: Temp/win/step7-8c-state.md (20/11, VM x64).
#   models.ps1 [-Provider cpu|dml|both] [-Only <subcadena del test>] [-TimeoutSec 1500] [-BuildTimeoutSec 3600]
# Salida: lineas "TF:<proveedor> <ok|FALLO|SALTO|TIMEOUT> <segundos> <Clase/test> :: causa o metricas". Codigo 1 si hay FALLO o TIMEOUT.
# Solo lectura de C:\ y de D:\tf-*; los modelos son los de la 7c (Vendor\models-win del checkout de la 7c, solo lectura).
param(
    [ValidateSet("cpu","dml","both")][string]$Provider = "both",
    [string]$Only = "",
    [int]$TimeoutSec = 1500,
    [int]$BuildTimeoutSec = 3600
)
. "$PSScriptRoot\common.ps1"

$ModelsDir = "D:\Personal\Guitar-Tool\Vendor\models-win"
$OrtCpu = Join-Path $TfOrt "onnxruntime.dll"
$OrtDml = "D:\tf-ort-dml\x64\onnxruntime.dll"
foreach ($p in @($ModelsDir, $OrtCpu, $OrtDml, $TfRtl)) {
    if (-not (Test-Path $p)) { Stop-Step 1 "falta $p" }
}
$env:Path = "$TfRtl;" + $env:Path
$swiftExe = (Get-Command swift.exe).Source
$Work = Join-Path $P9 "tmp\models"
New-Item -ItemType Directory -Force $Work | Out-Null

# Paquete, clase y tests (por metodo: la salida de print() sale al final del proceso y no se podria atribuir si fueran varios).
$Tests = @(
    @("StemKit",  "HeavyModelTests",          @("test0_ChunkMatchesMacReference", "test1_ExcerptThroughRunner", "test2_Input48kThroughRunner")),
    @("StemKit",  "LeadSeparatorHeavyTests",  @("test1_ParityWithTorchFixture", "test2_PlateroComposer")),
    @("StudyKit", "BeatHeavyModelTests",      @("test1_FixtureWithRealModel", "test2_SongsMatchP4")),
    @("StudyKit", "ChordHeavyModelTests",     @("testFixtureWindowsMatchPythonLogits", "testSongsMatchP4")),
    @("TabKit",   "BasicPitchHeavyModelTests", @("testParity", "testReportT1GuitarParts")),
    @("TabKit",   "DrumHeavyModelTests",      @("testFixtureParity", "testFullSongT1", "testLongSongWithContractChunks", "testChunkSeams")),
    @("StemKit",  "DirectMLParityTests",      @("test1_LeadRhythmDirectMLMatchesCpu", "test2_BSRoformerDirectMLMatchesCpu"))
)

# Lanza un proceso con tope: devuelve Rc, Timeout ($true si lo mato), Seconds y Lines (stdout y stderr).
function Invoke-Capped([string]$Exe, [string[]]$Arguments, [string]$Tag, [int]$Limit) {
    $o = Join-Path $Work "$Tag.out.txt"; $e = Join-Path $Work "$Tag.err.txt"
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $p = Start-Process -FilePath $Exe -ArgumentList ($Arguments -join " ") -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError $e
    $null = $p.Handle
    $timeout = $false
    if (-not $p.WaitForExit($Limit * 1000)) {
        $timeout = $true
        & taskkill.exe /PID $p.Id /T /F 2>&1 | Out-Null
        $p.WaitForExit(15000) | Out-Null
    }
    $sw.Stop()
    $lines = @()
    foreach ($f in @($o, $e)) { if (Test-Path $f) { $lines += @(Get-Content $f -ErrorAction SilentlyContinue | ForEach-Object { "$_" }) } }
    $rc = 124
    if (-not $timeout) { $rc = $p.ExitCode }
    return @{ Rc = $rc; Timeout = $timeout; Seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1); Lines = $lines }
}

$env:TF_MODEL_TESTS = "1"
$env:TF_MODELS_DIR = $ModelsDir

# Compilacion de los tres paquetes (una vez; los tests se lanzan luego con --skip-build).
$buildOk = @{}
foreach ($pkg in @("StemKit", "StudyKit", "TabKit")) {
    if ($Only -ne "" -and -not ($Tests | Where-Object { $_[0] -eq $pkg -and ($_[1] + " " + ($_[2] -join " ")) -like "*$Only*" })) { continue }
    $pkgPath = Join-Path $Repo "Packages\$pkg"
    $a = @("build", "--build-tests") + @(Get-SwiftArgs "debug" $pkgPath)
    $r = Invoke-Capped $swiftExe $a "build-$pkg" $BuildTimeoutSec
    $buildOk[$pkg] = ($r.Rc -eq 0)
    if ($r.Rc -eq 0) { Write-Output "TF:build $pkg ok $($r.Seconds) s" }
    else {
        Write-Output "TF:build $pkg FALLO rc=$($r.Rc) timeout=$($r.Timeout) $($r.Seconds) s"
        $r.Lines | Where-Object { $_ -match "error:" } | Select-Object -First 8 | ForEach-Object { Write-Output "TF:  $_" }
    }
}

function Short([string]$s, [int]$n) { if ($s.Length -gt $n) { return $s.Substring(0, $n) + "..." } else { return $s } }

$passes = @()
if ($Provider -in @("cpu", "both")) { $passes += ,@("cpu", $OrtCpu, "cpu") }
if ($Provider -in @("dml", "both")) { $passes += ,@("dml", $OrtDml, "DirectML") }
$bad = 0
$metricRe = "dB|argmax|fixture|golpes|\[7|PESADO|logits|notas|s/min|proveedor|transcribe|pico"
foreach ($ps in $passes) {
    $env:TF_ORT_DLL = $ps[1]
    $env:TF_ONNX_PROVIDER = $ps[2]
    foreach ($t in $Tests) {
        $pkg = $t[0]; $cls = $t[1]
        # DirectMLParity compara DirectML con CPU por dentro: solo en la pasada DirectML.
        if ($cls -eq "DirectMLParityTests" -and $ps[0] -ne "dml") { continue }
        foreach ($m in $t[2]) {
            $name = "$cls/$m"
            if ($Only -ne "" -and $name -notlike "*$Only*") { continue }
            if (-not $buildOk[$pkg]) { Write-Output "TF:$($ps[0]) FALLO 0 $name :: el paquete $pkg no compila"; $bad++; continue }
            $pkgPath = Join-Path $Repo "Packages\$pkg"
            $a = @("test", "--skip-build") + @(Get-SwiftArgs "debug" $pkgPath) + @("--filter", "$cls/$m")
            $r = Invoke-Capped $swiftExe $a "$($ps[0])-$cls-$m" $TimeoutSec
            $log = Join-Path $Work "$($ps[0])-$cls-$m.log"
            $r.Lines | Set-Content $log
            $status = "FALLO"; $secs = $r.Seconds; $cause = ""
            $caseLine = $r.Lines | Where-Object { $_ -match "Test Case '.*$m' (passed|failed|skipped)" } | Select-Object -Last 1
            if ($caseLine -match "(passed|failed|skipped) \(([0-9.]+) seconds\)") { $secs = $Matches[2] }
            if ($r.Timeout) { $status = "TIMEOUT"; $cause = "tope de $TimeoutSec s"; $bad++ }
            elseif ($caseLine -match "' passed") { $status = "ok" }
            elseif ($caseLine -match "' skipped") {
                $status = "SALTO"
                $sk = $r.Lines | Where-Object { $_ -match "(?i)skipped" -and $_ -notmatch "Test Case|Test Suite|Executed" } | Select-Object -First 1
                if ($sk) { $cause = Short (($sk -replace "^.*?(?i)skipped[: -]*", "").Trim()) 220 }
            }
            else {
                $bad++
                $er = $r.Lines | Where-Object { $_ -match "error:|Fatal error|crash|Exception" } | Select-Object -First 3
                if ($er) { $cause = Short (($er -join " | ")) 400 } else { $cause = "sin resultado de test (rc=$($r.Rc)); log $log" }
            }
            $metrics = ($r.Lines | Where-Object { $_ -match $metricRe -and $_ -notmatch "Test Case|Test Suite|Executed|error:" } | ForEach-Object { Short $_.Trim() 160 }) -join " | "
            if ($metrics) { $cause = (($cause + " " + $metrics).Trim()) }
            Write-Output "TF:$($ps[0]) $status $secs $name :: $(Short $cause 900)"
        }
    }
}
Write-Output "TF:logs por test en $Work"
if ($bad -gt 0) { exit 1 }
exit 0
