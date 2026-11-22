# Lanza tf_probe.exe CON VENTANA en la sesion interactiva (tarea programada tf-p9-run, creada y borrada en cada uso).
# Uso: run.ps1 -Tag <tag> -ArgsB64 <argumentos en base64 UTF-8> [-Timeout 240]
# Escribe out\run\<tag>.log (stdout+stderr), out\run\<tag>.code (codigo; 124 si se mato por tope) y sale con ese codigo.
# Se ejecuta EN EL PC. Todo fichero vive bajo $P9.
param([string]$Tag, [string]$ArgsB64, [int]$Timeout = 240)
. "$PSScriptRoot\common.ps1"
$RunOut = Join-Path $Out "run"
New-Item -ItemType Directory -Force $RunOut | Out-Null
$rel = Join-Path $AppDir "build\windows\x64\runner\Release"
$exe = Join-Path $rel "tf_probe.exe"
if (-not (Test-Path $exe)) { "error: falta $exe (pc.sh app)"; exit 1 }
$argLine = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ArgsB64))
$logF = Join-Path $RunOut "$Tag.log"
$errF = Join-Path $RunOut "$Tag.err"
$codeF = Join-Path $RunOut "$Tag.code"
$inner = Join-Path $RunOut "task-$Tag.ps1"
Remove-Item $logF, $errF, $codeF -ErrorAction SilentlyContinue

# Script interno (se ejecuta en la sesion interactiva).
@"
`$p = Start-Process -FilePath '$exe' -ArgumentList '$($argLine -replace "'", "''")' -WorkingDirectory '$rel' -PassThru -RedirectStandardOutput '$logF' -RedirectStandardError '$errF'
`$null = `$p.Handle
if (`$p.WaitForExit($($Timeout * 1000))) { `$c = `$p.ExitCode } else { Stop-Process -Id `$p.Id -Force -ErrorAction SilentlyContinue; `$c = 124 }
Set-Content -Path '$codeF' -Value `$c
"@ | Out-File $inner -Encoding ascii

$tn = "tf-p9-run"
$user = [Environment]::UserName
schtasks /Delete /TN $tn /F 2>&1 | Out-Null
$tr = "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$inner`""
schtasks /Create /TN $tn /TR $tr /SC ONCE /ST 23:59 /RU $user /IT /F 2>&1 | ForEach-Object { "$_" }
schtasks /Run /TN $tn 2>&1 | ForEach-Object { "$_" }
$sw = [Diagnostics.Stopwatch]::StartNew()
$limit = $Timeout + 60
while (-not (Test-Path $codeF) -and $sw.Elapsed.TotalSeconds -lt $limit) { Start-Sleep -Milliseconds 500 }
schtasks /Delete /TN $tn /F 2>&1 | Out-Null
$code = 125
if (Test-Path $codeF) { $code = [int](Get-Content $codeF | Select-Object -First 1) }
else { Get-Process tf_probe -ErrorAction SilentlyContinue | Stop-Process -Force }
Start-Sleep -Milliseconds 800
$left = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^tf_probe|AppCoreFFI|ffi-smoke' })
"TF:code=$code secs=$([math]::Round($sw.Elapsed.TotalSeconds,1)) leftover=$($left.Count)"
if ($left.Count -gt 0) { $left | ForEach-Object { "TF:leftover $($_.ProcessName) $($_.Id)" }; $left | Stop-Process -Force -ErrorAction SilentlyContinue }
exit $code
