# B3/B4, parte interna (sesion interactiva de tf, via schtasks /IT). Solo ASCII. Arranca ToneForge.exe sin activar la ventana,
# espera "eval| DONE b34part" en el log o el tope, mata la app, escribe <Work>\<Name>.done (0 ok, 124 tope, 2 murio).
# -DialogPath: si se da, maneja el selector nativo "Elegir carpeta" (UI Automation; sin probar en la VM) y deja <Name>.dialog.txt.
param([string]$Name, [string]$Work = "", [int]$LimitMin = 10, [string]$DialogPath = "")
$TfDrive = if ($env:TF_DRIVE) { $env:TF_DRIVE.TrimEnd('\') } else { "C:" }   # pass.ps1 la pone a la unidad del clon
if (-not $Work) { $Work = "$TfDrive\tf-qa\b34" }
$exe = if ($env:TF_EXE) { $env:TF_EXE } else { "$TfDrive/ToneForge/x64/ToneForge.exe" }
$log = Join-Path $Work "$Name.log"; $done = Join-Path $Work "$Name.done"; $dlg = Join-Path $Work "$Name.dialog.txt"
Remove-Item -Force $done, $log, $dlg -ErrorAction SilentlyContinue
$env:TF_LOG_FILE = $log
foreach ($pair in ((Get-Content -Raw (Join-Path $Work "$Name.env")).Trim() -split ";")) {
    $eq = $pair.IndexOf("="); if ($eq -gt 0) { Set-Item -Path ("Env:" + $pair.Substring(0, $eq).Trim()) -Value $pair.Substring($eq + 1) }
}
$argLine = (Get-Content -Raw (Join-Path $Work "$Name.args")).Trim()
$cs = @"
using System; using System.Runtime.InteropServices;
public static class B34Launch {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct STARTUPINFO { public int cb; public string lpReserved, lpDesktop, lpTitle; public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags; public short wShowWindow, cbReserved2; public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError; }
    [StructLayout(LayoutKind.Sequential)] struct PROCESS_INFORMATION { public IntPtr hProcess, hThread; public int dwProcessId, dwThreadId; }
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool CreateProcessW(string app, string cmd, IntPtr pa, IntPtr ta, bool inherit, uint flags, IntPtr env, string cwd, ref STARTUPINFO si, out PROCESS_INFORMATION pi);
    public static int Start(string exe, string args, string cwd) {
        STARTUPINFO si = new STARTUPINFO(); si.cb = Marshal.SizeOf(typeof(STARTUPINFO)); si.dwFlags = 1; si.wShowWindow = 4;
        PROCESS_INFORMATION pi;
        if (!CreateProcessW(exe, "\"" + exe + "\" " + args, IntPtr.Zero, IntPtr.Zero, false, 0, IntPtr.Zero, cwd, ref si, out pi)) return -Marshal.GetLastWin32Error();
        return pi.dwProcessId;
    }
}
"@
$procId = 0
try { Add-Type -TypeDefinition $cs -ErrorAction Stop; $procId = [B34Launch]::Start($exe, $argLine, (Split-Path $exe)) } catch { $procId = -1 }
if ($procId -le 0) { $procId = (Start-Process -FilePath $exe -ArgumentList $argLine -PassThru).Id }

function Drive-Dialog($pid1, $path) {
    Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
    $A = [System.Windows.Automation.AutomationElement]; $C = [System.Windows.Automation.Condition]
    $until = (Get-Date).AddSeconds(90)
    while ((Get-Date) -lt $until) {
        Start-Sleep -Milliseconds 700
        $pc = New-Object System.Windows.Automation.PropertyCondition($A::ProcessIdProperty, $pid1)
        $cc = New-Object System.Windows.Automation.PropertyCondition($A::ClassNameProperty, "#32770")
        $w = $A::RootElement.FindFirst("Children", (New-Object System.Windows.Automation.AndCondition($pc, $cc)))
        if (-not $w) { continue }
        Add-Content $dlg "dialogo encontrado: '$($w.Current.Name)'"
        try {
            $ed = $w.FindFirst("Descendants", (New-Object System.Windows.Automation.PropertyCondition($A::ControlTypeProperty, [System.Windows.Automation.ControlType]::Edit)))
            $vp = $ed.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern); $vp.SetValue($path)
            Add-Content $dlg "ruta escrita por ValuePattern: $path"
            $ok = $w.FindFirst("Descendants", (New-Object System.Windows.Automation.PropertyCondition($A::AutomationIdProperty, "1")))
            $ok.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
            Add-Content $dlg "boton aceptar invocado (AutomationId 1: '$($ok.Current.Name)')"; return
        } catch {
            Add-Content $dlg "UIA fallo ($_); pruebo SendKeys"
            try { Add-Type -AssemblyName System.Windows.Forms; $w.SetFocus(); Start-Sleep -Milliseconds 300
                  [System.Windows.Forms.SendKeys]::SendWait($path.Replace("{","{{}").Replace("}","{}}") + "{ENTER}"); Add-Content $dlg "SendKeys enviado"; return } catch { Add-Content $dlg "SendKeys fallo ($_)" }
        }
    }
    Add-Content $dlg "no aparecio el dialogo en 90 s"
}
if ($DialogPath -ne "") {
    # El dialogo solo existe tras el clic del guion (~10-20 s): se espera en segundo plano antes de manejarlo.
    Start-Sleep -Seconds 8; Drive-Dialog $procId $DialogPath
}
$code = 124; $until = (Get-Date).AddMinutes($LimitMin)
while ((Get-Date) -lt $until) {
    if (Test-Path $log) {
        try { $fs = [IO.File]::Open($log, "Open", "Read", "ReadWrite,Delete"); $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8); $text = $sr.ReadToEnd(); $sr.Dispose(); $fs.Dispose() } catch { $text = "" }
        if ($text -match "eval\| DONE b34part") { $code = 0; break }
    }
    if (-not (Get-Process -Id $procId -ErrorAction SilentlyContinue)) { $code = 2; break }
    Start-Sleep -Seconds 2
}
Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
Set-Content -Path $done -Value $code
