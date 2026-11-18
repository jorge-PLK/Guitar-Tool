# Arranca el producto en la sesion interactiva del usuario tf (tarea programada /IT).
# Si tf no tiene sesion grafica: "TF:GUI - SINSESION" y codigo 3.
# Salida: "TF:GUI <arch> <codigo>". Deja C:\ToneForge\gui-<arch>.txt y .png para traerlos por scp.
param(
    [string]$Product = "tf-smoke",
    [string]$Arch = "both",
    [int]$Wait = 8
)
$ErrorActionPreference = "Continue"
. "$PSScriptRoot\common.ps1"

# Sesion interactiva = un explorer.exe de tf en una sesion distinta de la 0.
$interactive = $false
foreach ($p in (Get-CimInstance Win32_Process -Filter "Name='explorer.exe'")) {
    $owner = Invoke-CimMethod -InputObject $p -MethodName GetOwner
    if ($owner.User -eq "tf" -and $p.SessionId -ne 0) { $interactive = $true }
}
if (-not $interactive) {
    Write-Output "TF:GUI - SINSESION"
    Write-Output "El usuario tf no tiene sesion grafica iniciada en la VM (inicia sesion en la ventana de UTM)."
    exit 3
}

$failed = $false
foreach ($a in (Get-Archs $Arch)) {
    $done = Join-Path $InstallRoot "gui-$a.done"
    Remove-Item -Force $done -ErrorAction SilentlyContinue
    $task = "tf-gui-$a"
    $script = Join-Path $PSScriptRoot "gui-task.ps1"
    $tr = "powershell -NoProfile -ExecutionPolicy Bypass -File $script -Product $Product -Arch $a -Wait $Wait"
    & schtasks /Create /TN $task /TR $tr /SC ONCE /ST 00:00 /RU tf /IT /F | Out-Null
    & schtasks /Run /TN $task | Out-Null
    $limit = (Get-Date).AddSeconds($Wait + 40)
    while (-not (Test-Path $done) -and (Get-Date) -lt $limit) { Start-Sleep -Milliseconds 500 }
    & schtasks /Delete /TN $task /F | Out-Null
    if (Test-Path $done) {
        $rc = [int](Get-Content $done | Select-Object -First 1)
        Write-Output "TF:GUI $a $rc"
        Get-Content (Join-Path $InstallRoot "gui-$a.txt") | ForEach-Object { Write-Output "  [$a] $_" }
        if ($rc -ne 0) { $failed = $true }
    } else {
        Write-Output "TF:GUI $a TIMEOUT"
        $failed = $true
    }
}
if ($failed) { exit 1 }
exit 0
