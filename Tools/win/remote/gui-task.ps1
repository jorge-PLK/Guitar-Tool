# Se ejecuta DENTRO de la sesion interactiva de tf (lo lanza gui.ps1 con schtasks /IT).
# Arranca el exe con --wait, captura la pantalla a los 3 s y escribe el codigo en gui-<arch>.done.
param(
    [string]$Product = "tf-smoke",
    [string]$Arch = "arm64",
    [int]$Wait = 8,
    [int]$Dummy = 0
)
$root = "C:\ToneForge"
$exe = Join-Path (Join-Path $root $Arch) "$Product.exe"
$out = Join-Path $root "gui-$Arch.txt"
$err = Join-Path $root "gui-$Arch.err"
$png = Join-Path $root "gui-$Arch.png"
$done = Join-Path $root "gui-$Arch.done"

# Si gui.ps1 dejo gui-<arch>.args, esos argumentos van tal cual (cadena unica) y el programa se mata si pasa de 75 s
# (codigo 124). gui-<arch>.env trae "NOMBRE=valor;OTRO=valor".
$argsFile = Join-Path $root "gui-$Arch.args"
$envFile = Join-Path $root "gui-$Arch.env"
$ArgsB64 = ""
$EnvB64 = ""
$argLine = "--wait $Wait"
$maxMs = -1
if (Test-Path $argsFile) {
    $argLine = (Get-Content -Raw $argsFile).Trim()
    $ArgsB64 = "x"
    $maxMs = 75000
}
if (Test-Path $envFile) { $EnvB64 = "x" }
# Log de diagnostico de la app: C:\ToneForge\toneforge-<arch>.log (build.sh lo trae a Temp/win/toneforge.log).
$logFile = Join-Path $root "toneforge-$Arch.log"
Remove-Item -Force $logFile -ErrorAction SilentlyContinue
$env:TF_LOG_FILE = $logFile
# -EnvB64: "NOMBRE=valor;OTRO=valor" en base64; se ponen en este proceso y el programa las hereda.
if ($EnvB64 -ne "") {
    $envText = (Get-Content -Raw $envFile).Trim()
    foreach ($pair in ($envText -split ";")) {
        $eq = $pair.IndexOf("=")
        if ($eq -gt 0) { Set-Item -Path ("Env:" + $pair.Substring(0, $eq).Trim()) -Value $pair.Substring($eq + 1) }
    }
}
# Con --snapshot-hold la ventana sigue abierta tras guardar el PNG: la captura del escritorio espera a que aparezca.
$snapPath = ""
if ($ArgsB64 -ne "" -and $argLine -match '--snapshot-hold' -and $argLine -match '--snapshot[ =]+"?([^" ]+)"?') {
    $snapPath = $Matches[1]
}
$p = Start-Process -FilePath $exe -ArgumentList $argLine -PassThru `
    -RedirectStandardOutput $out -RedirectStandardError $err
if ($snapPath -ne "") {
    $until = (Get-Date).AddSeconds(60)
    while (-not (Test-Path $snapPath) -and (Get-Date) -lt $until -and -not $p.HasExited) { Start-Sleep -Milliseconds 200 }
    Start-Sleep -Milliseconds 1200
} else {
    Start-Sleep -Seconds 3
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$b = [System.Windows.Forms.SystemInformation]::VirtualScreen
$bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
$bmp.Save($png, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose()
$bmp.Dispose()

$code = 0
if ($p.WaitForExit($maxMs)) {
    $code = $p.ExitCode
} else {
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    $code = 124
}
Set-Content -Path $done -Value $code
