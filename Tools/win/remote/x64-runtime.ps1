# Extrae las DLL del runtime de Swift para x64 a C:\tf-rtl-x64 (sin instalar nada).
# El Swift ARM64 de la VM solo instala el runtime ARM64; sin estas DLL, los tests x64 (XCTest y
# swift-testing enlazan swiftCore.dll en dinamico) mueren con 0xC000007B al cargar una DLL ARM64.
# Los .msm de Redistributables\<version> no se pueden desplegar con msiexec /a, asi que se lee el
# cabinet incrustado con la API COM de Windows Installer, se expande con expand.exe y se
# renombran los ficheros con la tabla File. Idempotente. ASCII puro, PowerShell 5.1.
# Salida: "TF:RTL x64 <ruta>" (o "TF:RTL x64 FALLO <motivo>" y codigo 1).
$ErrorActionPreference = "Stop"
$Dest = "C:\tf-rtl-x64"
if (Test-Path (Join-Path $Dest "swiftCore.dll")) {
    Write-Output "TF:RTL x64 $Dest"
    exit 0
}
try {
    $redist = Get-ChildItem "$env:LOCALAPPDATA\Programs\Swift\Redistributables" -Directory | Sort-Object Name | Select-Object -Last 1
    $msm = Join-Path $redist.FullName "rtl.shared.amd64.msm"
    $work = "C:\tf-rtl-work"
    if (Test-Path $work) { Remove-Item -Recurse -Force $work }
    New-Item -ItemType Directory -Force $work | Out-Null
    New-Item -ItemType Directory -Force $Dest | Out-Null
    $copy = Join-Path $work "rtl.msm"
    Copy-Item $msm $copy

    $inst = New-Object -ComObject WindowsInstaller.Installer
    $db = $inst.GetType().InvokeMember("OpenDatabase", "InvokeMethod", $null, $inst, @([string]$copy, [int]0))

    # 1. Cabinet incrustado -> rtl.cab (lectura en modo bytes, 1 MB por vez).
    $view = $db.GetType().InvokeMember("OpenView", "InvokeMethod", $null, $db, @("SELECT Name, Data FROM _Streams WHERE Name = 'MergeModule.CABinet'"))
    $view.GetType().InvokeMember("Execute", "InvokeMethod", $null, $view, $null)
    $rec = $view.GetType().InvokeMember("Fetch", "InvokeMethod", $null, $view, $null)
    $size = [int]$rec.GetType().InvokeMember("DataSize", "GetProperty", $null, $rec, @(2))
    $enc = [Text.Encoding]::GetEncoding(28591)
    $cab = Join-Path $work "rtl.cab"
    $fs = [IO.File]::Create($cab)
    $left = $size
    while ($left -gt 0) {
        $n = [Math]::Min($left, 1048576)
        $s = $rec.GetType().InvokeMember("ReadStream", "InvokeMethod", $null, $rec, @(2, $n, 1))
        $b = $enc.GetBytes($s)
        $fs.Write($b, 0, $b.Length)
        $left -= $n
    }
    $fs.Close()
    $out = Join-Path $work "out"
    New-Item -ItemType Directory -Force $out | Out-Null
    & expand.exe -F:* $cab $out | Out-Null

    # 2. Tabla File: clave -> nombre largo.
    $view2 = $db.GetType().InvokeMember("OpenView", "InvokeMethod", $null, $db, @('SELECT `File`, `FileName` FROM `File`'))
    $view2.GetType().InvokeMember("Execute", "InvokeMethod", $null, $view2, $null)
    while ($true) {
        $r = $view2.GetType().InvokeMember("Fetch", "InvokeMethod", $null, $view2, $null)
        if ($r -eq $null) { break }
        $key = $r.GetType().InvokeMember("StringData", "GetProperty", $null, $r, @(1))
        $name = $r.GetType().InvokeMember("StringData", "GetProperty", $null, $r, @(2))
        if ($name.Contains("|")) { $name = $name.Split("|")[1] }
        $src = Join-Path $out $key
        if (Test-Path $src) { Copy-Item $src (Join-Path $Dest $name) -Force }
    }
    $view = $null; $view2 = $null; $rec = $null; $r = $null; $db = $null; $inst = $null
    [GC]::Collect(); [GC]::WaitForPendingFinalizers()
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
    if (-not (Test-Path (Join-Path $Dest "swiftCore.dll"))) { throw "no aparece swiftCore.dll tras extraer" }
    Write-Output "TF:RTL x64 $Dest"
    exit 0
} catch {
    Write-Output "TF:RTL x64 FALLO $($_.Exception.Message) (linea $($_.InvocationInfo.ScriptLineNumber))"
    exit 1
}
