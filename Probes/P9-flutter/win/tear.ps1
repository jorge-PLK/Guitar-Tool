# Detector de desgarro (P9.7k). ASCII puro. Captura en bucle el area cliente de la ventana (CopyFromScreen) mientras la
# prueba de fotogramas corre con TF_P9_TEAR=1 (fondo negro + barra blanca vertical de 40 px, x avanza 16 px/fotograma)
# y mide, en 32 filas repartidas por la altura, la x del primer pixel blanco (>200 en B, G y R).
# Fotograma PARTIDO = las filas dan x que difieren en mas de 4 px, o algunas filas tienen barra y otras no.
# Debe correr EN LA SESION INTERACTIVA del escritorio (tarea programada, como run.ps1).
# Uso: tear.ps1 -Seconds 60 -Title <titulo de ventana o nombre de proceso> -Out <json> [-Region "x,y,w,h"]
#   -Region: sub-rectangulo del area cliente donde esta la textura (por defecto, todo el area cliente).
# Los PNG de hasta 5 capturas partidas se guardan junto al JSON (<Out sin extension>_tear<N>.png).
param([int]$Seconds = 60, [string]$Title = "", [string]$Out = "tear.json", [string]$Region = "")
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing @"
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public class TfTearRec { public double AtMs; public int[] Xs; public int Index; }

public class TfTearResult {
  public long Captures, NoBar, Torn;
  public double Elapsed;
  public List<TfTearRec> First = new List<TfTearRec>();
  public List<string> Pngs = new List<string>();
}

public static class TfTear {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential)] public struct PT { public int X, Y; }
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindow(string cls, string title);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref PT p);

  const int Rows = 32, Tolerance = 4, Thresh = 200, MaxSamples = 20, MaxPngs = 5;

  public static TfTearResult Run(IntPtr hwnd, double seconds, int rx, int ry, int rw, int rh, string pngBase) {
    RECT r; GetClientRect(hwnd, out r);
    PT pt = new PT(); ClientToScreen(hwnd, ref pt);
    int cw = r.R - r.L, ch = r.B - r.T;
    if (rw <= 0) { rx = 0; ry = 0; rw = cw; rh = ch; }
    if (rx + rw > cw) rw = cw - rx;
    if (ry + rh > ch) rh = ch - ry;
    if (rw < 8 || rh < Rows) throw new Exception("region demasiado pequena: " + rw + "x" + rh);
    int sx = pt.X + rx, sy = pt.Y + ry;
    int[] rowY = new int[Rows];
    for (int i = 0; i < Rows; i++) rowY[i] = (int)((long)i * (rh - 1) / (Rows - 1));
    int[] xs = new int[Rows];
    TfTearResult res = new TfTearResult();
    Stopwatch sw = Stopwatch.StartNew();
    using (Bitmap bmp = new Bitmap(rw, rh, PixelFormat.Format32bppArgb))
    using (Graphics g = Graphics.FromImage(bmp)) {
      Size sz = new Size(rw, rh);
      while (sw.Elapsed.TotalSeconds < seconds) {
        g.CopyFromScreen(sx, sy, 0, 0, sz);
        res.Captures++;
        BitmapData bd = bmp.LockBits(new Rectangle(0, 0, rw, rh), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        int found = 0, min = int.MaxValue, max = -1;
        try {
          for (int i = 0; i < Rows; i++) {
            IntPtr row = IntPtr.Add(bd.Scan0, rowY[i] * bd.Stride);
            byte[] line = new byte[rw * 4];
            Marshal.Copy(row, line, 0, line.Length);
            int x = -1;
            for (int px = 0; px < rw; px++) {
              int o = px * 4;
              if (line[o] > Thresh && line[o + 1] > Thresh && line[o + 2] > Thresh) { x = px; break; }
            }
            xs[i] = x;
            if (x >= 0) { found++; if (x < min) min = x; if (x > max) max = x; }
          }
        } finally { bmp.UnlockBits(bd); }
        if (found == 0) { res.NoBar++; continue; }
        bool torn = found < Rows || (max - min) > Tolerance;
        if (!torn) continue;
        res.Torn++;
        double at = sw.Elapsed.TotalMilliseconds;
        if (res.First.Count < MaxSamples) {
          TfTearRec rec = new TfTearRec(); rec.AtMs = Math.Round(at, 1); rec.Xs = (int[])xs.Clone(); rec.Index = (int)res.Captures;
          res.First.Add(rec);
        }
        if (res.Pngs.Count < MaxPngs) {
          string p = pngBase + "_tear" + (res.Pngs.Count + 1) + ".png";
          bmp.Save(p, ImageFormat.Png);
          res.Pngs.Add(p);
        }
      }
      res.Elapsed = sw.Elapsed.TotalSeconds;
    }
    return res;
  }
}
"@

[void][TfTear]::SetProcessDPIAware()
$h = [IntPtr]::Zero
if ($Title -ne "") {
  $h = [TfTear]::FindWindow($null, $Title)
  if ($h -eq [IntPtr]::Zero) {
    $name = [IO.Path]::GetFileNameWithoutExtension($Title)
    $p = Get-Process -Name $name -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } | Select-Object -First 1
    if ($p) { $h = $p.MainWindowHandle }
  }
}
if ($h -eq [IntPtr]::Zero) { "TF:tear sin ventana para '$Title'"; exit 1 }
$rx = 0; $ry = 0; $rw = 0; $rh = 0
if ($Region -ne "") { $v = $Region.Split(",") | ForEach-Object { [int]$_ }; $rx = $v[0]; $ry = $v[1]; $rw = $v[2]; $rh = $v[3] }
$outFull = [IO.Path]::GetFullPath($Out)
$base = [IO.Path]::Combine([IO.Path]::GetDirectoryName($outFull), [IO.Path]::GetFileNameWithoutExtension($outFull))
$res = [TfTear]::Run($h, [double]$Seconds, $rx, $ry, $rw, $rh, $base)
$n = [double]$res.Captures
$rep = [ordered]@{
  title = $Title; seconds = [math]::Round($res.Elapsed, 2); rows = 32; tolerancepx = 4; whiteThreshold = 200
  captures = $res.Captures
  capturesPerSecond = [math]::Round($n / $res.Elapsed, 1)
  noBarCaptures = $res.NoBar
  tornCaptures = $res.Torn
  tornPercent = if ($n -gt 0) { [math]::Round(100.0 * $res.Torn / $n, 3) } else { 0 }
  firstTorn = @($res.First | ForEach-Object { [ordered]@{ atMs = $_.AtMs; capture = $_.Index; xs = $_.Xs } })
  pngs = @($res.Pngs)
}
$rep | ConvertTo-Json -Depth 6 | Set-Content -Path $outFull -Encoding ASCII
"TF:tear captures=$($res.Captures) cps=$($rep.capturesPerSecond) noBar=$($res.NoBar) torn=$($res.Torn) ($($rep.tornPercent)%) -> $outFull"
