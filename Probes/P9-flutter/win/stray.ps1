# Solo lectura. Lista rutas de Flutter/Dart/pub bajo C:\Users\Jorge (con fecha) y cualquier fichero modificado desde -Since.
# Excluye AppData\Local\Temp y .swiftpm. Salida: "NAMED ..." (rutas conocidas) y "STRAY ..." (ficheros en la ventana).
param([string]$Since = "")
$h = "C:\Users\Jorge"
$t = if ($Since -ne "") { [datetime]::Parse($Since) } else { (Get-Date).AddHours(-3) }
"since $($t.ToString('yyyy-MM-dd HH:mm:ss'))"
$named = @("$h\AppData\Roaming\.flutter_settings", "$h\AppData\Roaming\.flutter_tool_state", "$h\AppData\Roaming\.dart",
           "$h\AppData\Roaming\.dart-tool", "$h\AppData\Local\Pub", "$h\AppData\Local\.dartServer", "$h\.pub-cache")
foreach ($p in $named + @(Get-ChildItem $h -Force -Filter ".dart*" -ErrorAction SilentlyContinue | ForEach-Object FullName) +
               @(Get-ChildItem $h -Force -Filter ".flutter*" -ErrorAction SilentlyContinue | ForEach-Object FullName) | Sort-Object -Unique) {
    if (Test-Path $p) { "NAMED $p  $((Get-Item $p -Force).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))" } else { "NAMED $p  (no existe)" }
}
# Ruido ajeno (navegadores, etc.) se descarta; el resto se informa.
$skip = '\\AppData\\Local\\Temp\\|\\\.swiftpm\\|Edge|Chrome|Google|NVIDIA|Discord|Spotify|Teams|OneDrive|Crashpad|\\Packages\\|Microsoft\\Windows|Microsoft\\Office|Brave|Firefox|Mozilla|Steam'
Get-ChildItem $h -Recurse -File -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -gt $t -and $_.FullName -notmatch $skip } |
    Select-Object -First 40 | ForEach-Object { "STRAY $($_.FullName)  $($_.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))" }
"fin"
