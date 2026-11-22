# Compila AppCoreFFI (release x64) y deja en out\core la DLL, el humo y las DLL que necesitan para cargarse.
# Escribe out\core.log y, al final, out\core.done con el codigo de salida. Se ejecuta EN EL PC (lo lanza pc.sh core).
. "$PSScriptRoot\common.ps1"
$log = Join-Path $Out "core.log"
$done = Join-Path $Out "core.done"
$lock = Join-Path $Out "core.running"
Remove-Item $done -ErrorAction SilentlyContinue
if (Test-Path $lock) { "error: ya hay un build en curso ($lock)" | Out-File $log -Encoding ascii; "1" | Out-File $done -Encoding ascii; exit 1 }
"running" | Out-File $lock -Encoding ascii
$start = Get-Date
$rc = 1
try {
    $swiftArgs = @("build") + @(Get-SwiftArgs)
    "TF:swift $($swiftArgs -join ' ')" | Out-File $log -Encoding ascii
    $sw = [Diagnostics.Stopwatch]::StartNew()
    & swift @swiftArgs 2>&1 | ForEach-Object { "$_" } | Out-File $log -Encoding ascii -Append
    $brc = $LASTEXITCODE
    $sw.Stop()
    "TF:BUILD rc=$brc $([math]::Round($sw.Elapsed.TotalSeconds,1)) s" | Out-File $log -Encoding ascii -Append
    if ($brc -ne 0) { throw "swift build fallo" }

    $bin = (& swift build @(Get-SwiftArgs) --show-bin-path 2>$null | Select-Object -Last 1).Trim()
    "TF:bin $bin" | Out-File $log -Encoding ascii -Append
    $dll = Join-Path $bin "AppCoreFFI.dll"
    if (-not (Test-Path $dll)) { throw "no existe $dll; DLLs en bin: $((Get-ChildItem $bin -Filter *.dll | ForEach-Object Name) -join ',')" }

    if (Test-Path $CoreOut) { Remove-Item $CoreOut -Recurse -Force }
    New-Item -ItemType Directory -Force $CoreOut | Out-Null
    Copy-Item $dll $CoreOut
    $smoke = Join-Path $bin "ffi-smoke-win.exe"
    if (Test-Path $smoke) { Copy-Item $smoke $CoreOut }

    # Cierre transitivo de importaciones: cada DLL importada que exista en el runtime de Swift, ORT o el bin se copia.
    $swiftBin = Split-Path (Get-Command swift.exe).Source
    $readobj = Join-Path $swiftBin "llvm-readobj.exe"
    $sources = @($bin, $TfRtl, $TfOrt)
    $queue = New-Object System.Collections.Queue
    $queue.Enqueue((Join-Path $CoreOut "AppCoreFFI.dll"))
    if (Test-Path $smoke) { $queue.Enqueue((Join-Path $CoreOut "ffi-smoke-win.exe")) }
    $copied = @{}
    while ($queue.Count -gt 0) {
        $f = $queue.Dequeue()
        $imports = & $readobj --coff-imports $f 2>$null | Where-Object { $_ -match "^\s*Name:\s+\S+\.dll" } | ForEach-Object { ($_ -split "Name:\s+")[1].Trim() }
        foreach ($name in ($imports | Sort-Object -Unique)) {
            if ($copied.ContainsKey($name.ToLower())) { continue }
            foreach ($s in $sources) {
                $p = Join-Path $s $name
                if (Test-Path $p) {
                    Copy-Item $p $CoreOut -Force
                    $copied[$name.ToLower()] = $s
                    $queue.Enqueue((Join-Path $CoreOut $name))
                    break
                }
            }
        }
    }
    # ONNX Runtime se carga en ejecucion (sin import lib): si la DLL lo lleva, DirectML y companeras van al lado.
    $bytes = [IO.File]::ReadAllBytes($dll)
    if ([Text.Encoding]::GetEncoding(28591).GetString($bytes).Contains("OrtGetApiBase")) {
        Get-ChildItem $TfOrt -Filter "*.dll" | ForEach-Object { Copy-Item $_.FullName $CoreOut -Force; $copied[$_.Name.ToLower()] = $TfOrt }
    }
    "TF:DLL copiadas ($($copied.Count)):" | Out-File $log -Encoding ascii -Append
    $copied.GetEnumerator() | Sort-Object Name | ForEach-Object { "TF:  $($_.Name) <- $($_.Value)" } | Out-File $log -Encoding ascii -Append
    $d = Get-Item (Join-Path $CoreOut "AppCoreFFI.dll")
    "TF:AppCoreFFI.dll $([math]::Round($d.Length / 1MB, 2)) MB" | Out-File $log -Encoding ascii -Append
    $exports = & $readobj --coff-exports (Join-Path $CoreOut "AppCoreFFI.dll") 2>$null | Where-Object { $_ -match "Name:\s+tf_" } | ForEach-Object { ($_ -split "Name:\s+")[1].Trim() }
    "TF:exportaciones tf_* ($(@($exports).Count)): $(@($exports) -join ' ')" | Out-File $log -Encoding ascii -Append
    $rc = 0
} catch {
    "error: $_" | Out-File $log -Encoding ascii -Append
} finally {
    "TF:total $([math]::Round(((Get-Date) - $start).TotalSeconds,1)) s" | Out-File $log -Encoding ascii -Append
    Remove-Item $lock -ErrorAction SilentlyContinue
    "$rc" | Out-File $done -Encoding ascii
}
exit $rc
