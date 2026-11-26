# Corre DENTRO de la sesion interactiva (lo lanza shot.ps1 con schtasks /IT). Arranca la app con carpetas de prueba nuevas
# bajo <repo>\Temp\flutter, captura el escritorio cuando la ventana lleva 1.5 s abierta y escribe shot.done con el codigo.
. "$PSScriptRoot\common.ps1"
$done = Join-Path $Shots "shot.done"
$rc = 1
try {
    $projects = Join-Path $Shots "shot-projects"
    $support = Join-Path $Shots "shot-support"
    foreach ($d in @($projects, $support)) {
        if (Test-Path $d) { Remove-Item $d -Recurse -Force }
        New-Item -ItemType Directory -Force $d | Out-Null
    }
    $snap = Join-Path $Shots "app-snapshot.png"
    $extra = (Get-Content -Raw (Join-Path $Shots "shot.args")).Trim()
    $delay = 5
    if ($extra -match '--snapshot-delay') { $delay = 0 }
    $argLine = "--projects-folder $projects --support-dir $support --snapshot $snap"
    if ($delay -gt 0) { $argLine += " --snapshot-delay $delay" }
    if ($extra -ne "") { $argLine += " $extra" }
    $exe = Get-Item $AppExe
    $p = Start-Process -FilePath $exe.FullName -ArgumentList $argLine -WorkingDirectory $ReleaseDir -PassThru `
        -RedirectStandardOutput (Join-Path $Shots "app.out") -RedirectStandardError (Join-Path $Shots "app.err")
    # Espera a la ventana principal y deja 1.5 s para que pinte.
    $until = (Get-Date).AddSeconds(30)
    while (-not $p.HasExited -and (Get-Date) -lt $until) {
        $p.Refresh()
        if ($p.MainWindowHandle -ne 0) { break }
        Start-Sleep -Milliseconds 200
    }
    if (-not $p.HasExited) { Start-Sleep -Milliseconds 1500 }
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
    $bmp.Save((Join-Path $Shots "desktop.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    if ($p.WaitForExit(60000)) { $rc = $p.ExitCode } else { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; $rc = 124 }
} catch {
    "error: $_" | Out-File (Join-Path $Shots "app.err") -Append -Encoding ascii
} finally {
    Set-Content -Path $done -Value $rc
}
