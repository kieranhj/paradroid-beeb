# Build Paradroid (BBC Model B) -> build/PARADROID.SSD
param([switch]$Run)

$ErrorActionPreference = 'Stop'
$root    = $PSScriptRoot
$beebasm = Join-Path $root 'bin\beebasm.exe'
$build   = Join-Path $root 'build'
$ssd     = Join-Path $build 'PARADROID.SSD'
$padded  = Join-Path $build 'PARADROID-200K.SSD'
$listing = Join-Path $build 'PARADROID.lst'
$bem     = 'C:\Users\khcon\OneDrive\BEEB\B-Em\b-em-42f6597-w64\b-em.exe'

if (-not (Test-Path $build)) { New-Item -ItemType Directory -Path $build | Out-Null }

# beebasm resolves INCLUDE relative to the working directory, so it runs from
# the project root and everything it produces is named into build/ instead.
#
# -v goes to STDOUT and is ~870 KB, so it is captured rather than printed. The
# progress and success messages go to STDERR and are left alone: redirecting
# those in PowerShell wraps each line in an ErrorRecord and trips
# $ErrorActionPreference even though the assembly succeeded. See CLAUDE.md.
# -opt 3 makes the disc *EXEC !BOOT on SHIFT+BREAK; main.asm assembles
# its own !BOOT (with the build timestamp) rather than using -boot.
& $beebasm -i (Join-Path $root 'src\main.asm') -do $ssd -opt 3 -title PARADROID -v |
    Out-File -FilePath $listing -Encoding utf8
if ($LASTEXITCODE -ne 0) { throw "beebasm failed ($LASTEXITCODE)" }

# A 200K copy for emulators. jsbeeb will not boot an unpadded image: beebasm's
# ends mid-track and jsbeeb refuses to read the last partial one, so the DFS
# FDC poll hangs loading PARASPR. See CLAUDE.md.
$bytes = [System.IO.File]::ReadAllBytes($ssd)
$pad   = New-Object byte[] (200KB)
[Array]::Copy($bytes, $pad, $bytes.Length)
[System.IO.File]::WriteAllBytes($padded, $pad)

"Built  $ssd"
"       $padded   padded, for jsbeeb"
"       $listing   assembly listing"

if ($Run) { & $bem -m3 $ssd }
