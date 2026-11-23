# P9 7j: inyector de teclas (SendInput) para `--case keys --keys-script` de las apps de WebView. ASCII puro, PowerShell 5.1.
# Protocolo (cabecera de webview\wv_all\lib\case_keys.dart): espera `ready:webview` en <Ready> -> teclea 1 2 3 q w e (150 ms),
# clic de raton en el centro de la ventana, teclea 4 5 6 -> espera `ready:field` -> teclea hola.
# Debe correr en la SESION INTERACTIVA (lo lanza el script interno de run.ps1 con -Keys). Uso: keys.ps1 -ProcId N -Ready ruta [-Log ruta]
param([int]$ProcId, [string]$Ready, [string]$Log = "", [int]$TimeoutSec = 120)
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class TfKeys {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk, wScan; public uint dwFlags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT { public int dx, dy; public uint mouseData, dwFlags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Explicit)] public struct IU { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
  [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public IU u; }
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint code, uint type);
  [DllImport("user32.dll", SetLastError = true)] public static extern uint SendInput(uint n, INPUT[] i, int size);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  public static uint Key(ushort vk, bool up) {
    INPUT[] a = new INPUT[1];
    a[0].type = 1; a[0].u.ki.wVk = vk; a[0].u.ki.wScan = (ushort)MapVirtualKey(vk, 0); a[0].u.ki.dwFlags = up ? 2u : 0u;
    return SendInput(1, a, Marshal.SizeOf(typeof(INPUT)));
  }
  public static uint Mouse(uint flags) {
    INPUT[] a = new INPUT[1];
    a[0].type = 0; a[0].u.mi.dwFlags = flags;
    return SendInput(1, a, Marshal.SizeOf(typeof(INPUT)));
  }
  public static void Foreground(IntPtr h) {
    keybd_event(0x12, 0, 0, UIntPtr.Zero); keybd_event(0x12, 0, 2, UIntPtr.Zero);  // Alt: permite SetForegroundWindow
    ShowWindow(h, 9); SetForegroundWindow(h);
  }
}
"@
[void][TfKeys]::SetProcessDPIAware()
function L($m) { if ($Log) { "$m" | Out-File $Log -Encoding ascii -Append } }
if ($Log) { "TF:keys start $((Get-Date).ToString('HH:mm:ss.fff'))" | Out-File $Log -Encoding ascii }

function Wait-Mark($mark) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
        if ((Test-Path $Ready) -and ((Get-Content $Ready -ErrorAction SilentlyContinue) -contains $mark)) { return $true }
        Start-Sleep -Milliseconds 50
    }
    return $false
}
function Get-Hwnd() {
    $p = Get-Process -Id $ProcId -ErrorAction SilentlyContinue
    if (-not $p) { return [IntPtr]::Zero }
    $p.Refresh(); return $p.MainWindowHandle
}
function Type-Keys([string]$s) {
    foreach ($ch in $s.ToUpper().ToCharArray()) {
        $vk = [uint16][int][char]$ch   # A-Z y 0-9: el VK es el codigo ASCII en mayusculas
        $d = [TfKeys]::Key($vk, $false); Start-Sleep -Milliseconds 30; $u = [TfKeys]::Key($vk, $true)
        L "key $ch down=$d up=$u fg=$([TfKeys]::GetForegroundWindow() -eq (Get-Hwnd))"
        Start-Sleep -Milliseconds 120   # 30 + 120 = 150 ms entre teclas
    }
}

if (-not (Wait-Mark "ready:webview")) { L "TF:keys timeout ready:webview"; exit 1 }
$h = Get-Hwnd
if ($h -eq [IntPtr]::Zero) { L "TF:keys sin ventana"; exit 1 }
[TfKeys]::Foreground($h); Start-Sleep -Milliseconds 300
L "TF:keys ready:webview fg=$([TfKeys]::GetForegroundWindow() -eq $h)"
Type-Keys "123qwe"
$r = New-Object TfKeys+RECT
[void][TfKeys]::GetWindowRect($h, [ref]$r)
$cx = [int](($r.L + $r.R) / 2); $cy = [int](($r.T + $r.B) / 2)
[void][TfKeys]::SetCursorPos($cx, $cy); Start-Sleep -Milliseconds 100
[void][TfKeys]::Mouse(2); Start-Sleep -Milliseconds 40; [void][TfKeys]::Mouse(4)   # LEFTDOWN, LEFTUP
L "TF:keys clic en $cx,$cy (ventana $($r.L),$($r.T),$($r.R),$($r.B))"
Start-Sleep -Milliseconds 300
Type-Keys "456"
if (-not (Wait-Mark "ready:field")) { L "TF:keys timeout ready:field"; exit 1 }
[TfKeys]::Foreground($h); Start-Sleep -Milliseconds 200
Type-Keys "hola"
L "TF:keys fin"
exit 0
