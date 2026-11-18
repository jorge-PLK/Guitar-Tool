# Comun a los scripts remotos de Tools/win/build.sh. ASCII puro, PowerShell 5.1.
$env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User")

$TfRoot = "C:\tf"
$InstallRoot = "C:\ToneForge"

# Argumentos de swift build para una arquitectura ("arm64" o "x64").
function Get-SwiftArgs([string]$arch) {
    $a = @("-c", "release", "--static-swift-stdlib")
    if ($arch -eq "x64") { $a += @("--arch", "x86_64") }
    return $a
}

function Get-Archs([string]$arch) {
    if ($arch -eq "both") { return @("arm64", "x64") }
    return @($arch)
}
