# Captura de pantalla del area cliente de la ventana principal de un proceso (CopyFromScreen). ASCII puro.
# Se ejecuta EN LA SESION INTERACTIVA (lo lanza el script interno de run.ps1). Uso: shot.ps1 -ProcId N -Png ruta
param([int]$ProcId, [string]$Png)
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class TfWin {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential)] public struct PT { public int X, Y; }
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref PT p);
}
"@
[void][TfWin]::SetProcessDPIAware()
$p = Get-Process -Id $ProcId -ErrorAction SilentlyContinue
if (-not $p) { "TF:shot sin proceso $ProcId"; exit 1 }
$p.Refresh()
$h = $p.MainWindowHandle
if ($h -eq [IntPtr]::Zero) { "TF:shot sin ventana"; exit 1 }
$r = New-Object TfWin+RECT
[void][TfWin]::GetClientRect($h, [ref]$r)
$pt = New-Object TfWin+PT
[void][TfWin]::ClientToScreen($h, [ref]$pt)
$w = $r.R - $r.L; $hh = $r.B - $r.T
$bmp = New-Object Drawing.Bitmap $w, $hh
$g = [Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($pt.X, $pt.Y, 0, 0, (New-Object Drawing.Size $w, $hh))
$bmp.Save($Png, [Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
"TF:shot ${w}x${hh} at $($pt.X),$($pt.Y) -> $Png"
