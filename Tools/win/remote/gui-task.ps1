# Se ejecuta DENTRO de la sesion interactiva de tf (lo lanza gui.ps1 con schtasks /IT).
# Arranca el exe con --wait, captura la pantalla a los 3 s y escribe el codigo en gui-<arch>.done.
param(
    [string]$Product = "tf-smoke",
    [string]$Arch = "arm64",
    [int]$Wait = 8
)
$root = "C:\ToneForge"
$exe = Join-Path (Join-Path $root $Arch) "$Product.exe"
$out = Join-Path $root "gui-$Arch.txt"
$err = Join-Path $root "gui-$Arch.err"
$png = Join-Path $root "gui-$Arch.png"
$done = Join-Path $root "gui-$Arch.done"

$p = Start-Process -FilePath $exe -ArgumentList @("--wait", "$Wait") -PassThru `
    -RedirectStandardOutput $out -RedirectStandardError $err
Start-Sleep -Seconds 3

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$b = [System.Windows.Forms.SystemInformation]::VirtualScreen
$bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
$bmp.Save($png, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose()
$bmp.Dispose()

$p.WaitForExit()
Set-Content -Path $done -Value $p.ExitCode
