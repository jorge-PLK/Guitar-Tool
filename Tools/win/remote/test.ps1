# swift test del paquete en C:\tf para una o las dos arquitecturas (-Config debug por defecto; release solo para medir
# tiempos: -c release con -enable-testing para @testable; sin instalar ni arrancar).
# Salida: por arquitectura una linea "TF:TEST <arch> <estado> <segundos> <rc>" y despues la salida
# de swift con prefijo "  [<arch>] ". Estado: OK (rc 0), FALLO (hubo tests y fallaron), COMPILA o TIMEOUT.
# TIMEOUT: se paso del tope total (-TimeoutSec, por defecto 600) o no hubo salida nueva del test en
# -IdleSec (por defecto 180); 0 = sin tope. Se mata el arbol de procesos y, tras la linea TEST, sigue
#   TF:TIMEOUT <arch> <total|inactividad> <procesos vivos tras matar> :: <ultimo test arrancado>
# Un TIMEOUT en una arquitectura no impide correr la otra.
# Codigo: 0 bien, 1 fallos de tests o TIMEOUT, 2 no compila (o no hay Package.swift).
param(
    [string]$Package = "Tools/win/smoke",
    [string]$Arch = "both",
    [string]$Filter = "",
    [int]$TimeoutSec = 600,
    [int]$IdleSec = 180,
    [ValidateSet("debug","release")][string]$Config = "debug",
    # Variables de entorno para el test, "TF_A=1;TF_B=C:\x" (build.sh las toma de TF_VM_ENV). Solo nombres TF_*.
    [string]$SetEnv = ""
)
$ErrorActionPreference = "Continue"
. "$PSScriptRoot\common.ps1"
. "$PSScriptRoot\limited.ps1"

foreach ($kv in ($SetEnv -split ";")) {
    if ($kv -match "^(TF_[A-Za-z0-9_]+)=(.*)$") { Set-Item -Path "env:$($Matches[1])" -Value $Matches[2] }
}

$pkgPath = Join-Path $TfRoot ($Package -replace "/", "\")
if (-not (Test-Path (Join-Path $pkgPath "Package.swift"))) {
    Write-Output "TF:TEST - COMPILA 0 2"
    Write-Output "error: no existe Package.swift en $pkgPath"
    exit 2
}

$cfgArgs = @()
if ($Config -eq "release") { $cfgArgs = @("-c", "release", "-Xswiftc", "-enable-testing") }
$worst = 0
foreach ($a in (Get-Archs $Arch)) {
    $swiftArgs = @("test", "--package-path", $pkgPath) + $cfgArgs
    if ($a -eq "x64") {
        # swift test no admite --static-swift-stdlib: el runner x64 necesita las DLL x64 de Swift.
        $rtl = & "$PSScriptRoot\x64-runtime.ps1" | Where-Object { $_ -like "TF:RTL*" }
        Write-Output $rtl
        if ($rtl -like "*FALLO*") {
            Write-Output "TF:TEST x64 COMPILA 0 1"
            Write-Output "  [x64] error: no se pudo preparar el runtime x64 de Swift"
            $worst = 2
            continue
        }
        $env:Path = "C:\tf-rtl-x64;" + $env:Path
        $swiftArgs += @("--arch", "x86_64")
    }
    if ($Filter -ne "") { $swiftArgs += @("--filter", $Filter) }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $outFile = "C:\tf-run-$a.txt"
    $timedOut = $null
    $lines = @()
    $rc = 0
    # ONNX Runtime: compila primero los tests y, si importan onnxruntime.dll, la deja junto al .dll de tests.
    $buildArgs = @("build", "--build-tests", "--package-path", $pkgPath) + $cfgArgs
    if ($a -eq "x64") { $buildArgs += @("--arch", "x86_64") }
    $b = Invoke-Limited "swift" $buildArgs $outFile $TimeoutSec 0
    if ($b.Reason -ne "") {
        $timedOut = $b
        $lines = $b.Lines
        $lastTest = "(compilando, ningun test arrancado)"
        $rc = 124
    } else {
        $bin = (& swift @buildArgs --show-bin-path 2>$null | Select-Object -Last 1)
        if ($bin -and (Test-Path $bin)) {
            Get-ChildItem $bin -Filter "*Tests.dll" -File | ForEach-Object { [void](Copy-OrtDlls $a $bin $_.FullName) }
        }
        $remaining = 0
        if ($TimeoutSec -gt 0) { $remaining = [int][math]::Max(1, $TimeoutSec - [int]$sw.Elapsed.TotalSeconds) }
        $r = Invoke-Limited "swift" $swiftArgs $outFile $remaining $IdleSec
        $lines = $r.Lines
        $rc = $r.Rc
        if ($r.Reason -ne "") {
            $timedOut = $r
            $lastTest = Get-LastStartedTest $lines
        }
    }
    $sw.Stop()
    $secs = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    $ran = $false
    foreach ($l in $lines) {
        if ($l -match "Executed [0-9]+ tests?" -or $l -match "Test run with [0-9]+ tests?") { $ran = $true }
    }
    if ($timedOut) {
        $state = "TIMEOUT"
        if ($worst -lt 1) { $worst = 1 }
    } elseif ($rc -eq 0) {
        $state = "OK"
    } elseif ($ran) {
        $state = "FALLO"
        if ($worst -lt 1) { $worst = 1 }
    } else {
        $state = "COMPILA"
        $worst = 2
    }
    Write-Output "TF:TEST $a $state $secs $rc"
    if ($timedOut) { Write-Output "TF:TIMEOUT $a $($timedOut.Reason) $($timedOut.Left) :: $lastTest" }
    $lines | ForEach-Object { Write-Output "  [$a] $_" }
}
exit $worst
