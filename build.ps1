# Build Paradroid (BBC Model B) -> PARADROID.SSD
param([switch]$Run)

$ErrorActionPreference = 'Stop'
$root    = $PSScriptRoot
$beebasm = Join-Path $root 'bin\beebasm.exe'
$ssd     = Join-Path $root 'PARADROID.SSD'
$bem     = 'C:\Users\khcon\OneDrive\BEEB\B-Em\b-em-42f6597-w64\b-em.exe'

& $beebasm -i (Join-Path $root 'src\main.asm') -do $ssd -boot PARA -v
if ($LASTEXITCODE -ne 0) { throw "beebasm failed ($LASTEXITCODE)" }
"Built $ssd"

if ($Run) { & $bem -m3 $ssd }
