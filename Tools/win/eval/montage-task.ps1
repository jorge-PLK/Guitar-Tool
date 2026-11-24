# Montaje-export, parte interna: se ejecuta DENTRO de la sesion interactiva de tf (la lanza montage-launch.ps1 con schtasks /IT). Solo ASCII.
# Arranca ToneForge.exe sin activar la ventana (SW_SHOWNOACTIVATE), espera la linea "DONE montage" del log de la app o el tope,
# mata la app, lista los temporales de exportacion que queden en %TEMP% de tf y escribe el codigo en <Work>\montage-<Mode>.done
# (0 = salio la linea DONE, 124 = tope, 2 = la app murio antes).
param(
    [string]$Mode = "full",
    [string]$Work = "",
    [int]$LimitMin = 45
)
$TfDrive = if ($env:TF_DRIVE) { $env:TF_DRIVE.TrimEnd('\') } else { "C:" }   # pass.ps1 la pone a la unidad del clon
if (-not $Work) { $Work = "$TfDrive\tf-qa\montage" }
$exe = "$TfDrive\ToneForge\x64\ToneForge.exe"
$argsFile = Join-Path $Work "montage-$Mode.args"
$envFile = Join-Path $Work "montage-$Mode.env"
$log = Join-Path $Work "app-$Mode.log"
$done = Join-Path $Work "montage-$Mode.done"
$tempList = Join-Path $Work "montage-$Mode.temp.txt"
Remove-Item -Force $done, $log, $tempList -ErrorAction SilentlyContinue

# Temporales de exportacion previos (para distinguir los nuevos).
$before = @(Get-ChildItem $env:TEMP -Filter "tf-montage-export-*" -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })

# Entorno: "NOMBRE=valor;OTRO=valor" (el valor puede llevar ':' y '\'). TF_LOG_FILE siempre.
$env:TF_LOG_FILE = $log
foreach ($pair in ((Get-Content -Raw $envFile).Trim() -split ";")) {
    $eq = $pair.IndexOf("=")
    if ($eq -gt 0) { Set-Item -Path ("Env:" + $pair.Substring(0, $eq).Trim()) -Value $pair.Substring($eq + 1) }
}
$argLine = (Get-Content -Raw $argsFile).Trim()

$cs = @"
using System;
using System.Runtime.InteropServices;
public static class MontageLaunch {
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
    $procId = [MontageLaunch]::Start($exe, $argLine, (Split-Path $exe))
} catch { $procId = -1 }
if ($procId -le 0) {
    $p = Start-Process -FilePath $exe -ArgumentList $argLine -PassThru
    $procId = $p.Id
    Add-Content -Path (Join-Path $Work "montage-$Mode.launch.txt") -Value "Start-Process (sin NOACTIVATE)"
} else {
    Set-Content -Path (Join-Path $Work "montage-$Mode.launch.txt") -Value "CreateProcess SW_SHOWNOACTIVATE pid $procId"
}

$code = 124
$until = (Get-Date).AddMinutes($LimitMin)
while ((Get-Date) -lt $until) {
    Start-Sleep -Seconds 2
    if (Test-Path $log) {
        $fs = $null
        try {
            $fs = [IO.File]::Open($log, "Open", "Read", "ReadWrite,Delete")
            $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)
            $text = $sr.ReadToEnd()
            $sr.Dispose()
        } catch { $text = "" } finally { if ($fs) { $fs.Dispose() } }
        if ($text -match "eval\| DONE montage") { $code = 0; break }
    }
    if (-not (Get-Process -Id $procId -ErrorAction SilentlyContinue)) { $code = 2; break }
}
# Margen para que la app cierre sus limpiezas antes de contar restos; luego se mata.
Start-Sleep -Seconds 2
Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
$after = @(Get-ChildItem $env:TEMP -Filter "tf-montage-export-*" -Force -ErrorAction SilentlyContinue | Where-Object { $before -notcontains $_.FullName })
$lines = @("TEMP de tf: $env:TEMP; temporales tf-montage-export-* nuevos: $($after.Count)")
foreach ($d in $after) {
    $files = @(Get-ChildItem $d.FullName -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer })
    $lines += ("  {0} ({1} ficheros, {2} bytes)" -f $d.FullName, $files.Count, ($files | Measure-Object Length -Sum).Sum)
}
Set-Content -Path $tempList -Value $lines
Set-Content -Path $done -Value $code
