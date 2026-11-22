# Solo lectura: lista ficheros recientes (ultimas 3 h) en sitios donde swift/clang podrian haber escrito fuera de Temp\p9.
$t = (Get-Date).AddHours(-3)
$skip = 'Edge|Chrome|Google|NVIDIA|Discord|Spotify|Teams|OneDrive|Packages\\|Microsoft\\(Windows|Edge|Office|OneDrive|Teams)|Crashpad'
foreach ($d in @("$env:USERPROFILE\AppData\Local", "$env:USERPROFILE\AppData\Roaming", "$env:USERPROFILE\.swiftpm", "$env:USERPROFILE\.cache", "C:\Windows\Temp", "$env:SystemDrive\tf")) {
    if (-not (Test-Path $d)) { continue }
    Get-ChildItem $d -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -gt $t -and $_.FullName -notmatch $skip } |
        Select-Object -First 15 -ExpandProperty FullName
}
"fin"
