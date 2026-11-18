# Una sola vez: inicio de sesion automatico de tf y sin bloqueo ni suspension. Requiere administrador.
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File setup-autologin.ps1 -Password <contrasena>
# La contrasena queda en claro en el registro (Winlogon\DefaultPassword); VM local de pruebas.
param(
    [Parameter(Mandatory = $true)][string]$Password,
    [string]$User = "tf"
)
$ErrorActionPreference = "Stop"

$wl = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
Set-ItemProperty -Path $wl -Name AutoAdminLogon -Value "1" -Type String
Set-ItemProperty -Path $wl -Name DefaultUserName -Value $User -Type String
Set-ItemProperty -Path $wl -Name DefaultPassword -Value $Password -Type String
Set-ItemProperty -Path $wl -Name DefaultDomainName -Value $env:COMPUTERNAME -Type String

# Windows 11: que no exija Windows Hello / pida contrasena en el inicio.
$pl = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device"
if (-not (Test-Path $pl)) { New-Item -Path $pl -Force | Out-Null }
Set-ItemProperty -Path $pl -Name DevicePasswordLessBuildVersion -Value 0 -Type DWord

# Sin suspension, sin apagar pantalla y sin pedir contrasena al despertar.
& powercfg /change standby-timeout-ac 0
& powercfg /change standby-timeout-dc 0
& powercfg /change monitor-timeout-ac 0
& powercfg /change monitor-timeout-dc 0
& powercfg /change hibernate-timeout-ac 0
& powercfg /setacvalueindex SCHEME_CURRENT SUB_NONE CONSOLELOCK 0
& powercfg /setdcvalueindex SCHEME_CURRENT SUB_NONE CONSOLELOCK 0
& powercfg /setactive SCHEME_CURRENT

# Sin bloqueo por inactividad ni salvapantallas.
$sys = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
Set-ItemProperty -Path $sys -Name InactivityTimeoutSecs -Value 0 -Type DWord
$cp = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Control Panel\Desktop"
if (-not (Test-Path $cp)) { New-Item -Path $cp -Force | Out-Null }
Set-ItemProperty -Path $cp -Name ScreenSaveActive -Value "0" -Type String

Write-Output "autologin configurado para $User en $env:COMPUTERNAME; reinicia la VM para comprobarlo"
