# Detector de desgarro (P9.7k). ASCII puro. Captura en bucle el area cliente de la ventana (CopyFromScreen) mientras la
# prueba de fotogramas corre con TF_P9_TEAR=1 (fondo negro + barra blanca vertical de 40 px, x avanza 16 px/fotograma)
# y mide, en 32 filas repartidas por la altura, la x del primer pixel blanco (>200 en B, G y R).
# Fotograma PARTIDO = las filas dan x que difieren en mas de 4 px, o algunas filas tienen barra y otras no.
# Debe correr EN LA SESION INTERACTIVA del escritorio (tarea programada, como run.ps1).
# Uso: tear.ps1 -Seconds 60 -Title <titulo de ventana o nombre de proceso> -Out <json> [-Region "x,y,w,h"]
#   -Region: sub-rectangulo del area cliente donde esta la textura (por defecto, todo el area cliente).
# P9 7g (fps de WebView): -Series anade al JSON la serie de x por captura y sus metricas (posiciones distintas por segundo, mayor
#   paron, ratio distintas/capturas); -TopLogical <px logicos> recorta esa franja superior (barra de Flutter) escalada con el DPI
#   de la ventana (GetDpiForWindow/96), asi la region sale en pixeles fisicos a cualquier escala. Sin ellos el modo es el de 7f.
# Los PNG de hasta 5 capturas partidas se guardan junto al JSON (<Out sin extension>_tear<N>.png).
param([int]$Seconds = 60, [string]$Title = "", [string]$Out = "tear.json", [string]$Region = "", [int]$Delay = 0, [switch]$Series, [double]$TopLogical = 0)
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
  public List<double> T = new List<double>();  // 7g: instante (ms) y x (-1 = sin barra) de cada captura
  public List<int> X = new List<int>();
}

public class TfSeries {
  public long Valid, Changes;
  public double MeanPerSec, MinPerSec, MaxPerSec, LongestStallMs, DistinctRatio;
  public int Windows;
}

public static class TfTear {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential)] public struct PT { public int X, Y; }
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
  public static int[] ClientSize(IntPtr h) { RECT r; GetClientRect(h, out r); return new int[] { r.R - r.L, r.B - r.T }; }
  // Metricas de la serie: "cambio" = x distinta de la de la captura valida anterior (las partidas cuentan con su x minima).
  public static TfSeries Analyze(TfTearResult res) {
    TfSeries s = new TfSeries(); s.MinPerSec = double.MaxValue;
    int win = (int)Math.Floor(res.Elapsed);
    int[] per = new int[Math.Max(win, 0)];
    int prev = -2; double runStart = 0, longest = 0, lastT = 0;
    for (int i = 0; i < res.X.Count; i++) {
      if (res.X[i] < 0) continue;
      s.Valid++; lastT = res.T[i];
      if (prev == -2) { prev = res.X[i]; runStart = res.T[i]; continue; }
      if (res.X[i] != prev) {
        s.Changes++;
        double stall = res.T[i] - runStart; if (stall > longest) longest = stall;
        int w = (int)(res.T[i] / 1000.0); if (w >= 0 && w < per.Length) per[w]++;
        prev = res.X[i]; runStart = res.T[i];
      }
    }
    if (lastT - runStart > longest) longest = lastT - runStart;
    s.LongestStallMs = Math.Round(longest, 1);
    s.Windows = per.Length;
    double sum = 0, mx = 0;
    foreach (int c in per) { sum += c; if (c < s.MinPerSec) s.MinPerSec = c; if (c > mx) mx = c; }
    if (per.Length == 0) s.MinPerSec = 0;
    s.MaxPerSec = mx;
    s.MeanPerSec = res.Elapsed > 0 ? Math.Round(s.Changes / res.Elapsed, 2) : 0;
    s.DistinctRatio = res.Captures > 0 ? Math.Round((double)s.Changes / res.Captures, 4) : 0;
    return s;
  }
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindow(string cls, string title);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref PT p);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  // Al frente, sin tapar: HWND_TOPMOST (-1), SWP_NOMOVE|SWP_NOSIZE (3).
  public static void Front(IntPtr h) { ShowWindow(h, 9); SetWindowPos(h, new IntPtr(-1), 0, 0, 0, 0, 3); SetForegroundWindow(h); }

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
        if (res.Captures == 1 || res.Captures == 200) bmp.Save(pngBase + "_cap" + res.Captures + ".png", ImageFormat.Png);  // capturas normales de referencia
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
        res.T.Add(sw.Elapsed.TotalMilliseconds); res.X.Add(found == 0 ? -1 : min);
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
$wait = [Diagnostics.Stopwatch]::StartNew()
while ($h -eq [IntPtr]::Zero -and $wait.Elapsed.TotalSeconds -lt 30) {
  if ($Title -ne "") {
    $h = [TfTear]::FindWindow($null, $Title)
    if ($h -eq [IntPtr]::Zero) {
      $name = [IO.Path]::GetFileNameWithoutExtension($Title)
      $p = Get-Process -Name $name -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } | Select-Object -First 1
      if ($p) { $h = $p.MainWindowHandle }
    }
  }
  if ($h -eq [IntPtr]::Zero) { Start-Sleep -Milliseconds 300 }
}
if ($h -eq [IntPtr]::Zero) { "TF:tear sin ventana para '$Title'"; exit 1 }
[TfTear]::Front($h)
if ($Delay -gt 0) { Start-Sleep -Seconds $Delay }
$rx = 0; $ry = 0; $rw = 0; $rh = 0
$dpiScale = [double][TfTear]::GetDpiForWindow($h) / 96.0
if ($Region -eq "" -and $TopLogical -gt 0) {
  $cs = [TfTear]::ClientSize($h); $top = [int][math]::Round($TopLogical * $dpiScale)
  $Region = "0,$top,$($cs[0]),$($cs[1] - $top)"
}
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
if ($Series) {
  $a = [TfTear]::Analyze($res)
  $rep.dpiScale = $dpiScale
  $rep.region = "$rx,$ry,$rw,$rh"
  $rep.series = [ordered]@{
    validCaptures = $a.Valid; distinctPositions = $a.Changes; distinctRatio = $a.DistinctRatio
    distinctPerSecMean = $a.MeanPerSec; distinctPerSecMin = $a.MinPerSec; distinctPerSecMax = $a.MaxPerSec
    windows1s = $a.Windows; longestStallMs = $a.LongestStallMs
  }
}
$rep | ConvertTo-Json -Depth 6 | Set-Content -Path $outFull -Encoding ASCII
"TF:tear captures=$($res.Captures) cps=$($rep.capturesPerSecond) noBar=$($res.NoBar) torn=$($res.Torn) ($($rep.tornPercent)%) -> $outFull"
