# B2, parte interna: se ejecuta DENTRO de la sesion interactiva de tf (la lanza b2-launch.ps1 con schtasks /IT). Solo ASCII.
# Arranca ToneForge.exe sin activar la ventana (SW_SHOWNOACTIVATE) y vigila el log de la app cada 1 s:
#  - cada linea "eval| DISK <etiqueta> <ruta>" -> foto de la carpeta (ficheros, bytes, lista) en <Work>\b2-disk-<Phase>.tsv
#  - "eval| DONE b2" -> mata la app y escribe el codigo en <Work>\b2-<Phase>.done (0 = salio DONE, 124 = tope, 2 = la app murio antes)
param(
    [string]$Phase = "a",
    [string]$Work = "",
    [int]$LimitMin = 45
)
$TfDrive = if ($env:TF_DRIVE) { $env:TF_DRIVE.TrimEnd('\') } else { "C:" }   # pass.ps1 la pone a la unidad del clon
if (-not $Work) { $Work = "$TfDrive\tf-qa\b2" }
$exe = if ($env:TF_EXE) { $env:TF_EXE } else { "$TfDrive/ToneForge/x64/ToneForge.exe" }
$argsFile = Join-Path $Work "b2-$Phase.args"
$envFile = Join-Path $Work "b2-$Phase.env"
$log = Join-Path $Work "app-$Phase.log"
$done = Join-Path $Work "b2-$Phase.done"
$tsv = Join-Path $Work "b2-disk-$Phase.tsv"
Remove-Item -Force $done, $log, $tsv -ErrorAction SilentlyContinue

$env:TF_LOG_FILE = $log
foreach ($pair in ((Get-Content -Raw $envFile).Trim() -split ";")) {
    $eq = $pair.IndexOf("=")
    if ($eq -gt 0) { Set-Item -Path ("Env:" + $pair.Substring(0, $eq).Trim()) -Value $pair.Substring($eq + 1) }
}
$argLine = (Get-Content -Raw $argsFile).Trim()

$cs = @"
using System;
using System.Runtime.InteropServices;
public static class B2Launch {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct STARTUPINFO { public int cb; public string lpReserved, lpDesktop, lpTitle; public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags; public short wShowWindow, cbReserved2; public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError; }
    [StructLayout(LayoutKind.Sequential)]
    struct PROCESS_INFORMATION { public IntPtr hProcess, hThread; public int dwProcessId, dwThreadId; }
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool CreateProcessW(string app, string cmd, IntPtr pa, IntPtr ta, bool inherit, uint flags, IntPtr env, string cwd, ref STARTUPINFO si, out PROCESS_INFORMATION pi);
    public static int Start(string exe, string args, string cwd) {
        STARTUPINFO si = new STARTUPINFO(); si.cb = Marshal.SizeOf(typeof(STARTUPINFO));
        si.dwFlags = 1; si.wShowWindow = 4;   // STARTF_USESHOWWINDOW + SW_SHOWNOACTIVATE
        PROCESS_INFORMATION pi;
        if (!CreateProcessW(exe, "\"" + exe + "\" " + args, IntPtr.Zero, IntPtr.Zero, false, 0, IntPtr.Zero, cwd, ref si, out pi)) return -Marshal.GetLastWin32Error();
        return pi.dwProcessId;
    }
}
"@
$procId = 0
try {
    Add-Type -TypeDefinition $cs -ErrorAction Stop
    $procId = [B2Launch]::Start($exe, $argLine, (Split-Path $exe))
} catch { $procId = -1 }
if ($procId -le 0) {
    $p = Start-Process -FilePath $exe -ArgumentList $argLine -PassThru
    $procId = $p.Id
    Add-Content -Path (Join-Path $Work "b2-$Phase.launch.txt") -Value "Start-Process (sin NOACTIVATE)"
} else {
    Set-Content -Path (Join-Path $Work "b2-$Phase.launch.txt") -Value "CreateProcess SW_SHOWNOACTIVATE pid $procId"
}

# Foto de una carpeta: etiqueta, ruta, ficheros, bytes, subcarpetas, existe, lista (hasta 40 «ruta:bytes»).
function Snap([string]$label, [string]$path) {
    $exists = Test-Path -LiteralPath $path
    $files = @(); $dirs = @()
    if ($exists) {
        $files = @(Get-ChildItem -LiteralPath $path -Recurse -Force -File -ErrorAction SilentlyContinue)
        $dirs = @(Get-ChildItem -LiteralPath $path -Recurse -Force -Directory -ErrorAction SilentlyContinue)
    }
    $bytes = ($files | Measure-Object -Property Length -Sum).Sum
    if (-not $bytes) { $bytes = 0 }
    $root = $path.TrimEnd('\')
    $list = ($files | Select-Object -First 40 | ForEach-Object { $_.FullName.Substring([Math]::Min($root.Length + 1, $_.FullName.Length)) + ":" + $_.Length }) -join ";"
    Add-Content -Path $tsv -Encoding UTF8 -Value ("{0}`t{1}`t{2}`t{3}`t{4}`t{5}`t{6}" -f $label, $path, $files.Count, $bytes, $dirs.Count, $exists, $list)
}

$code = 124
$seen = 0
$until = (Get-Date).AddMinutes($LimitMin)
while ((Get-Date) -lt $until) {
    Start-Sleep -Seconds 1
    $text = ""
    if (Test-Path $log) {
        $fs = $null
        try {
            $fs = [IO.File]::Open($log, "Open", "Read", "ReadWrite,Delete")
            $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)
            $text = $sr.ReadToEnd()
            $sr.Dispose()
        } catch { $text = "" } finally { if ($fs) { $fs.Dispose() } }
    }
    if ($text) {
        $ms = [regex]::Matches($text, "eval\| DISK (\S+) ([^\r\n]+)")
        while ($seen -lt $ms.Count) { Snap $ms[$seen].Groups[1].Value $ms[$seen].Groups[2].Value.Trim(); $seen++ }
        if ($text -match "eval\| DONE b2") { $code = 0; break }
    }
    if (-not (Get-Process -Id $procId -ErrorAction SilentlyContinue)) { $code = 2; break }
}
Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
Set-Content -Path $done -Value $code
