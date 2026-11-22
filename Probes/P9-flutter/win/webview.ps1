# P9.7e: compila (release, windows x64) las apps minimas de WebView y las arranca 5 s. EN EL PC (lo lanza pc.sh webview).
# Candidata(s): lee out\webview.arg (vacio = wv_all, wv_flutter, wv_inapp). Una que falla no para las demas.
# Escribe out\webview.log (TF:...), out\webview\<cand>.log (build completo) y out\webview.done.
. "$PSScriptRoot\common.ps1"
Set-FlutterEnv
$log = Join-Path $Out "webview.log"
$done = Join-Path $Out "webview.done"
$WvOut = Join-Path $Out "webview"
New-Item -ItemType Directory -Force $WvOut | Out-Null
Remove-Item $done -ErrorAction SilentlyContinue
function L($m) { "$m" | Out-File $log -Encoding ascii -Append }
"TF:start $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))" | Out-File $log -Encoding ascii
$rc = 1
try {
    if (-not (Test-Path $Flutter)) { throw "falta $Flutter" }
    # Runtime Evergreen de WebView2 (solo lectura del registro).
    $guid = "{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}"
    $pv = $null
    foreach ($k in @("HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\$guid", "HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\$guid", "HKCU:\SOFTWARE\Microsoft\EdgeUpdate\Clients\$guid")) {
        $v = (Get-ItemProperty $k -ErrorAction SilentlyContinue).pv
        if ($v) { $pv = "$v ($k)"; break }
    }
    if (-not $pv) { $pv = "AUSENTE" }
    L "TF:webview2-runtime $pv"
    L "TF:flutter $((& $Flutter --no-version-check --version 2>&1 | Select-Object -First 1))"

    # flutter_inappwebview_windows busca nuget.exe en el PATH (CMake: NUGET-NOTFOUND). Sin instalar nada: un nuget.exe suelto en <P9>\tools.
    $tools = Join-Path $P9 "tools"
    New-Item -ItemType Directory -Force $tools | Out-Null
    $nuget = Join-Path $tools "nuget.exe"
    if (-not (Test-Path $nuget)) {
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe" -OutFile $nuget -UseBasicParsing } catch { L "TF:nuget.exe descarga fallo: $_" }
    }
    if (Test-Path $nuget) { $env:Path = "$tools;$env:Path"; L "TF:nuget.exe en $tools" }

    $argF = Join-Path $Out "webview.arg"
    $want = if (Test-Path $argF) { ((Get-Content $argF -Raw) -replace '\s', '') } else { "" }
    $cands = if ($want) { @($want) } else { @("wv_all", "wv_flutter", "wv_inapp") }

    foreach ($c in $cands) {
        # Sufijo -short: construye una copia en <P9>\w\<cand> (ruta corta, por el limite MAX_PATH de MSBuild).
        $base = $c -replace '-short$', ''
        $dir = Join-Path $Src "Probes\P9-flutter\webview\$base"
        $clog = Join-Path $WvOut "$c.log"
        "TF:start $c" | Out-File $clog -Encoding ascii
        if (-not (Test-Path $dir)) { L "TF:$c compila=NO (falta $dir)"; continue }
        if ($c -ne $base) {
            $sdir = Join-Path $P9 "w\$base"
            robocopy $dir $sdir /MIR /XD build .dart_tool ephemeral /NFL /NDL /NJH /NJS /NP | Out-Null
            $dir = $sdir
            L "TF:$c copia corta en $dir (largo de ruta del .exe: $(($dir + '\build\windows\x64\runner\Release\' + $base + '.exe').Length))"
        }
        Push-Location $dir
        $sw = [Diagnostics.Stopwatch]::StartNew()
        & $Flutter --no-version-check pub get 2>&1 | ForEach-Object { "$_" } | Out-File $clog -Encoding ascii -Append
        $prc = $LASTEXITCODE
        $brc = 99
        if ($prc -eq 0) {
            & $Flutter --no-version-check build windows --release 2>&1 | ForEach-Object { "$_" } | Out-File $clog -Encoding ascii -Append
            $brc = $LASTEXITCODE
        }
        $sw.Stop()
        Pop-Location
        $secs = [math]::Round($sw.Elapsed.TotalSeconds, 1)
        # Versiones resueltas del pubspec.lock.
        $lock = Join-Path $dir "pubspec.lock"
        $vers = @()
        if (Test-Path $lock) {
            $name = ""
            foreach ($ln in (Get-Content $lock)) {
                if ($ln -match '^  ([a-z0-9_]+):\s*$') { $name = $Matches[1] }
                elseif ($name -match 'webview' -and $ln -match '^    version: "(.+)"') { $vers += "$name=$($Matches[1])" }
            }
        }
        L "TF:$c versiones: $($vers -join ' ')"
        $rel = Join-Path $dir "build\windows\x64\runner\Release"
        $exe = Join-Path $rel "$base.exe"
        if ($prc -ne 0 -or $brc -ne 0 -or -not (Test-Path $exe)) {
            L "TF:$c compila=NO pubget=$prc build=$brc ${secs}s (log out\webview\$c.log)"
            $err = Select-String -Path $clog -Pattern 'error|Error|fatal|not found|Cannot|failed' | Select-Object -First 8
            foreach ($e in $err) { L "TF:$c ERR $($e.Line.Trim())" }
            continue
        }
        $size = [math]::Round(((Get-ChildItem $rel -Recurse -File | Measure-Object Length -Sum).Sum) / 1MB, 1)
        $dlls = @(Get-ChildItem $rel -Filter *.dll | Where-Object { $_.Name -ne 'flutter_windows.dll' } | ForEach-Object Name) -join ','
        $warn = @(Select-String -Path $clog -Pattern 'warning' ).Count
        L "TF:$c compila=SI ${secs}s Release=${size}MB dlls=[$dlls] avisos_build=$warn"

        # Arranque de humo con ventana (tarea programada, sesion interactiva).
        $codeF = Join-Path $WvOut "$c.code"
        $inner = Join-Path $WvOut "task-$c.ps1"
        Remove-Item $codeF -ErrorAction SilentlyContinue
        @"
`$p = Start-Process -FilePath '$exe' -ArgumentList '--exit-after 5' -WorkingDirectory '$rel' -PassThru -RedirectStandardOutput '$WvOut\$c.out' -RedirectStandardError '$WvOut\$c.err'
`$null = `$p.Handle
if (`$p.WaitForExit(30000)) { `$cc = `$p.ExitCode } else { Stop-Process -Id `$p.Id -Force -ErrorAction SilentlyContinue; `$cc = 124 }
Set-Content -Path '$codeF' -Value `$cc
"@ | Out-File $inner -Encoding ascii
        $tn = "tf-p9-wv"
        schtasks /Delete /TN $tn /F 2>&1 | Out-Null
        $tr = "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$inner`""
        schtasks /Create /TN $tn /TR $tr /SC ONCE /ST 23:59 /RU ([Environment]::UserName) /IT /F 2>&1 | Out-Null
        schtasks /Run /TN $tn 2>&1 | Out-Null
        $sw2 = [Diagnostics.Stopwatch]::StartNew()
        while (-not (Test-Path $codeF) -and $sw2.Elapsed.TotalSeconds -lt 90) { Start-Sleep -Milliseconds 500 }
        schtasks /Delete /TN $tn /F 2>&1 | Out-Null
        $code = 125
        if (Test-Path $codeF) { $code = [int](Get-Content $codeF | Select-Object -First 1) }
        Start-Sleep -Milliseconds 800
        $left = @(Get-Process -Name $base -ErrorAction SilentlyContinue)
        $left | Stop-Process -Force -ErrorAction SilentlyContinue
        $errTxt = ""
        $ef = Join-Path $WvOut "$c.err"
        if ((Test-Path $ef) -and (Get-Item $ef).Length -gt 0) { $errTxt = " stderr=" + ((Get-Content $ef -TotalCount 2) -join ' | ') }
        L "TF:$c arranque code=$code secs=$([math]::Round($sw2.Elapsed.TotalSeconds,1)) murio_solo=$(if ($code -eq 0) {'SI'} else {'NO'}) leftover=$($left.Count)$errTxt"
    }
    $rc = 0
} catch {
    L "error: $_"
} finally {
    "$rc" | Out-File $done -Encoding ascii
}
exit $rc
