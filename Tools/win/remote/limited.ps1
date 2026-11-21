# Ejecuta un programa con tope de tiempo total y vigilante de inactividad (Fase 7c). Solo ASCII.
# Se carga con: . "$PSScriptRoot\limited.ps1"
# La salida (stdout+stderr) va a un fichero que se sondea; si no crece en IdleSec, o se pasa de TotalSec,
# se mata el arbol entero (taskkill /F /T) y se barren por nombre los procesos de swift/xctest.
# TotalSec/IdleSec 0 = sin tope.

$script:TfKillNames = @("swift", "swift-test", "swift-build", "swift-run", "swift-frontend", "swiftc",
    "swift-driver", "swiftpm-testing-helper", "xctest", "clang", "lld-link")

# Mata el arbol de $Proc y barre por nombre. Devuelve cuantos procesos siguen vivos tras reintentar.
function Stop-TfTree($Proc) {
    if ($Proc -and -not $Proc.HasExited) { & taskkill /F /T /PID $Proc.Id 2>&1 | Out-Null }
    $left = 0
    for ($i = 0; $i -lt 10; $i++) {
        $ps = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
            $script:TfKillNames -contains $_.ProcessName -or $_.ProcessName -like "*xctest*" })
        $left = $ps.Count
        if ($left -eq 0) { break }
        $ps | ForEach-Object { & taskkill /F /T /PID $_.Id 2>&1 | Out-Null }
        Start-Sleep -Milliseconds 500
    }
    return $left
}

# Lee un fichero que otro proceso aun tiene abierto.
function Read-SharedLines([string]$Path) {
    if (-not (Test-Path $Path)) { return @() }
    $fs = [IO.File]::Open($Path, "Open", "Read", "ReadWrite,Delete")
    try {
        $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)
        $txt = $sr.ReadToEnd()
    } finally { $fs.Dispose() }
    return @($txt -split "`r?`n")
}

# Devuelve objeto: Rc, Reason ("" | "total" | "inactividad"), Left (procesos vivos tras matar), Lines.
function Invoke-Limited([string]$Exe, [string[]]$ArgList, [string]$OutFile, [int]$TotalSec, [int]$IdleSec) {
    if (Test-Path $OutFile) { Remove-Item -Force $OutFile -ErrorAction SilentlyContinue }
    $inner = '"' + $Exe + '"'
    foreach ($x in $ArgList) { $inner += ' "' + $x + '"' }
    $inner += ' > "' + $OutFile + '" 2>&1'
    $p = Start-Process -FilePath "cmd.exe" -ArgumentList ('/d /s /c "' + $inner + '"') -NoNewWindow -PassThru
    $null = $p.Handle
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $idle = [Diagnostics.Stopwatch]::StartNew()
    $lastLen = -1
    $reason = ""
    $left = 0
    while (-not $p.WaitForExit(500)) {
        $len = 0
        if (Test-Path $OutFile) { $len = (Get-Item $OutFile).Length }
        if ($len -ne $lastLen) { $lastLen = $len; $idle.Restart() }
        if ($TotalSec -gt 0 -and $sw.Elapsed.TotalSeconds -ge $TotalSec) { $reason = "total"; break }
        if ($IdleSec -gt 0 -and $idle.Elapsed.TotalSeconds -ge $IdleSec) { $reason = "inactividad"; break }
    }
    $rc = 0
    if ($reason -ne "") {
        $left = Stop-TfTree $p
        $rc = 124
    } else {
        $rc = $p.ExitCode
    }
    $lines = @(Read-SharedLines $OutFile | Where-Object { $_ -ne "System.Management.Automation.RemoteException" -and $_.Trim() -ne "" })
    Remove-Item -Force $OutFile -ErrorAction SilentlyContinue
    return [pscustomobject]@{ Rc = $rc; Reason = $reason; Left = $left; Lines = $lines }
}

# Ultimo test arrancado en una salida de XCTest o swift-testing.
function Get-LastStartedTest($Lines) {
    $last = ""
    foreach ($l in $Lines) {
        if ($l -match "Test Case '[^']*' started" -or $l -match "Test .* started") { $last = $l.Trim() }
    }
    if ($last -eq "") { return "(ninguno)" }
    return $last
}
