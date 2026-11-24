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
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  // Al frente, sin tapar: Alt sintetico (permite SetForegroundWindow desde fuera del proceso en primer plano),
  // restaurar, HWND_TOPMOST (-1) con SWP_NOMOVE|SWP_NOSIZE (3).
  public static void Front(IntPtr h) {
    keybd_event(0x12, 0, 0, UIntPtr.Zero); keybd_event(0x12, 0, 2, UIntPtr.Zero);
    ShowWindow(h, 9); SetWindowPos(h, new IntPtr(-1), 0, 0, 0, 0, 3); SetForegroundWindow(h);
  }
}
"@
[void][TfWin]::SetProcessDPIAware()
$p = Get-Process -Id $ProcId -ErrorAction SilentlyContinue
if (-not $p) { "TF:shot sin proceso $ProcId"; exit 1 }
$p.Refresh()
$h = $p.MainWindowHandle
if ($h -eq [IntPtr]::Zero) { "TF:shot sin ventana"; exit 1 }
[TfWin]::Front($h)
Start-Sleep -Milliseconds 700   # deja que DWM componga y que Flutter pinte (una ventana tapada deja de recibir vsync)
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
