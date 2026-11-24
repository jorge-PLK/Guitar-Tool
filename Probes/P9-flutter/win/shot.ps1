# Captura del area cliente de la ventana principal de un proceso (CopyFromScreen). ASCII puro.
# Se ejecuta EN LA SESION INTERACTIVA (lo lanza el script interno de run.ps1). Uso: shot.ps1 -ProcId N -Png ruta
# Salidas (P9 7h, diagnostico): <Png> (cliente por pantalla), <Png sin .png>.pw.png (PrintWindow con PW_RENDERFULLCONTENT = 2,
# solo esa ventana), <Png sin .png>.screen.png (pantalla completa) y <Png sin .png>.info.txt (ventanas del PID y ventana en
# primer plano tras SetForegroundWindow: PID, titulo, clase, rect).
param([int]$ProcId, [string]$Png)
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text;
public static class TfWin {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential)] public struct PT { public int X, Y; }
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref PT p);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr h);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
  // Al frente, sin tapar: Alt sintetico (permite SetForegroundWindow desde fuera del proceso en primer plano),
  // restaurar, HWND_TOPMOST (-1) con SWP_NOMOVE|SWP_NOSIZE (3).
  public static void Front(IntPtr h) {
    keybd_event(0x12, 0, 0, UIntPtr.Zero); keybd_event(0x12, 0, 2, UIntPtr.Zero);
    ShowWindow(h, 9); SetWindowPos(h, new IntPtr(-1), 0, 0, 0, 0, 3); SetForegroundWindow(h);
  }
  public static string Describe(IntPtr h) {
    if (h == IntPtr.Zero) return "(ninguna)";
    uint pid; GetWindowThreadProcessId(h, out pid);
    StringBuilder t = new StringBuilder(256), c = new StringBuilder(256);
    GetWindowText(h, t, 256); GetClassName(h, c, 256);
    RECT w, cl; GetWindowRect(h, out w); GetClientRect(h, out cl);
    return "hwnd=0x" + h.ToInt64().ToString("X") + " pid=" + pid + " title='" + t + "' class=" + c + " rect=" + w.L + "," + w.T + "," + w.R + "," + w.B +
      " client=" + (cl.R - cl.L) + "x" + (cl.B - cl.T) + " visible=" + IsWindowVisible(h) + " iconic=" + IsIconic(h) + " zoomed=" + IsZoomed(h);
  }
  public static List<string> OfPid(uint want) {
    List<string> o = new List<string>();
    EnumWindows(delegate(IntPtr h, IntPtr l) { uint pid; GetWindowThreadProcessId(h, out pid); if (pid == want) o.Add(Describe(h)); return true; }, IntPtr.Zero);
    return o;
  }
}
"@
[void][TfWin]::SetProcessDPIAware()
$p = Get-Process -Id $ProcId -ErrorAction SilentlyContinue
if (-not $p) { "TF:shot sin proceso $ProcId"; exit 1 }
$p.Refresh()
$h = $p.MainWindowHandle
if ($h -eq [IntPtr]::Zero) { "TF:shot sin ventana"; exit 1 }
$base = $Png -replace '\.png$', ''
$info = @()
$info += "pid objetivo: $ProcId  MainWindowHandle: 0x$($h.ToInt64().ToString('X'))  MainWindowTitle: '$($p.MainWindowTitle)'"
$info += "pantalla: $([TfWin]::GetSystemMetrics(0))x$([TfWin]::GetSystemMetrics(1))"
$info += "antes: " + [TfWin]::Describe($h)
[TfWin]::Front($h)
Start-Sleep -Milliseconds 700   # deja que DWM componga y que Flutter pinte (una ventana tapada deja de recibir vsync)
$info += "primer plano tras Front: " + [TfWin]::Describe([TfWin]::GetForegroundWindow())
$info += "ventana tras Front: " + [TfWin]::Describe($h)
foreach ($l in [TfWin]::OfPid([uint32]$ProcId)) { $info += "ventana del pid: $l" }
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
# Pantalla completa.
$sw = [TfWin]::GetSystemMetrics(0); $sh = [TfWin]::GetSystemMetrics(1)
$sb = New-Object Drawing.Bitmap $sw, $sh
$sg = [Drawing.Graphics]::FromImage($sb)
$sg.CopyFromScreen(0, 0, 0, 0, (New-Object Drawing.Size $sw, $sh))
$sb.Save("$base.screen.png", [Drawing.Imaging.ImageFormat]::Png)
$sg.Dispose(); $sb.Dispose()
# Solo la ventana (PrintWindow, PW_RENDERFULLCONTENT = 2): no depende de lo que la tape.
$wr = New-Object TfWin+RECT
[void][TfWin]::GetWindowRect($h, [ref]$wr)
$ww = $wr.R - $wr.L; $wh = $wr.B - $wr.T
if ($ww -gt 0 -and $wh -gt 0) {
  $pb = New-Object Drawing.Bitmap $ww, $wh
  $pg = [Drawing.Graphics]::FromImage($pb)
  $hdc = $pg.GetHdc()
  $okPw = [TfWin]::PrintWindow($h, $hdc, 2)
  $pg.ReleaseHdc($hdc)
  $pb.Save("$base.pw.png", [Drawing.Imaging.ImageFormat]::Png)
  $pg.Dispose(); $pb.Dispose()
  $info += "PrintWindow ok=$okPw ${ww}x${wh} -> $base.pw.png"
}
$info += "cliente: ${w}x${hh} at $($pt.X),$($pt.Y) -> $Png"
Set-Content -Path "$base.info.txt" -Value $info -Encoding ascii
$info | ForEach-Object { "TF:shot $_" }
