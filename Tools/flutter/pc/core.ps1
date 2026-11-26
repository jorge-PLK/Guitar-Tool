# Compila AppCoreFFI (release x64) y deja en <P9>\f7core la DLL y el cierre de DLL que necesita (runtime de Swift, ORT).
# Referencia: Probes\P9-flutter\win\core.ps1.
. "$PSScriptRoot\common.ps1"
$start = Get-Date
$swiftArgs = @("build", "--product", "AppCoreFFI") + @(Get-SwiftArgs "release")
Write-Output "TF:swift $($swiftArgs -join ' ')"
& swift @swiftArgs 2>&1 | ForEach-Object { "$_" }
if ($LASTEXITCODE -ne 0) { Stop-Step 1 "swift build" }

$bin = (& swift build @(Get-SwiftArgs "release") --show-bin-path 2>$null | Select-Object -Last 1).Trim()
$dll = Join-Path $bin "AppCoreFFI.dll"
if (-not (Test-Path $dll)) { Stop-Step 1 "no existe $dll" }
if ((Get-Item $dll).LastWriteTime -lt $start.AddSeconds(-1)) { Write-Output "TF:aviso AppCoreFFI.dll no se regenero en esta pasada (build incremental sin cambios)" }

if (Test-Path $Stage) { Remove-Item $Stage -Recurse -Force }
New-Item -ItemType Directory -Force $Stage | Out-Null
Copy-Item $dll $Stage

# Cierre transitivo de importaciones: cada DLL importada que exista en bin, el runtime de Swift o ORT se copia.
$swiftBin = Split-Path (Get-Command swift.exe).Source
$readobj = Join-Path $swiftBin "llvm-readobj.exe"
$sources = @($bin, $TfRtl, $TfOrt)
$queue = New-Object System.Collections.Queue
$queue.Enqueue((Join-Path $Stage "AppCoreFFI.dll"))
$copied = @{}
$missing = @{}
while ($queue.Count -gt 0) {
    $f = $queue.Dequeue()
    $imports = & $readobj --coff-imports $f 2>$null | Where-Object { $_ -match "^\s*Name:\s+\S+\.dll" } | ForEach-Object { ($_ -split "Name:\s+")[1].Trim() }
    foreach ($name in ($imports | Sort-Object -Unique)) {
        if ($copied.ContainsKey($name.ToLower())) { continue }
        $found = $false
        foreach ($s in $sources) {
            $p = Join-Path $s $name
            if (Test-Path $p) {
                Copy-Item $p $Stage -Force
                $copied[$name.ToLower()] = $s
                $queue.Enqueue((Join-Path $Stage $name))
                $found = $true
                break
            }
        }
        if (-not $found -and -not (Test-Path (Join-Path $env:SystemRoot "System32\$name")) -and $name -notmatch '^(api-ms-|ext-ms-)') { $missing[$name] = 1 }
    }
}
# ONNX Runtime se carga en ejecucion (sin import lib): si la DLL lo lleva, DirectML y companeras van al lado.
$text = [Text.Encoding]::GetEncoding(28591).GetString([IO.File]::ReadAllBytes($dll))
if ($text.Contains("OrtGetApiBase")) {
    Get-ChildItem $TfOrt -Filter "*.dll" | ForEach-Object { Copy-Item $_.FullName $Stage -Force; $copied[$_.Name.ToLower()] = $TfOrt }
}
if ($missing.Count -gt 0) { Write-Output "TF:importaciones sin resolver (no estan en System32 ni en las fuentes): $(($missing.Keys | Sort-Object) -join ' ')" }
$d = Get-Item (Join-Path $Stage "AppCoreFFI.dll")
Write-Output "TF:AppCoreFFI.dll $([math]::Round($d.Length / 1MB, 2)) MB $($d.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Output "TF:DLL en $Stage ($((Get-ChildItem $Stage -Filter *.dll).Count)): $((Get-ChildItem $Stage -Filter *.dll | ForEach-Object Name) -join ' ')"
exit 0
