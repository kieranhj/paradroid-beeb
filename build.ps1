# Build Paradroid (BBC Model B) -> build/PARADROID.SSD
param([switch]$Run)

$ErrorActionPreference = 'Stop'
$root    = $PSScriptRoot
$beebasm = Join-Path $root 'bin\beebasm.exe'
$build   = Join-Path $root 'build'
$raw     = Join-Path $build 'PARADROID-raw.ssd'
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
& $beebasm -i (Join-Path $root 'src\main.asm') -do $raw -opt 3 -title PARADROID -v |
    Out-File -FilePath $listing -Encoding utf8
if ($LASTEXITCODE -ne 0) { throw "beebasm failed ($LASTEXITCODE)" }

# Post-process: ZX0-compress the four bank files, lay the disc out in boot
# access order, and write the padded copy jsbeeb needs (it will not boot an
# unpadded image - beebasm's ends mid-track and the DFS FDC poll hangs).
# THE RAW IMAGE IS NOT BOOTABLE: the loader expects compressed streams at
# DEPK_STREAM. Never hand $raw to an emulator. See tools/make_disc.py.
python (Join-Path $root 'tools\make_disc.py') $raw $ssd $padded
if ($LASTEXITCODE -ne 0) { throw "make_disc failed ($LASTEXITCODE)" }

"Built  $ssd"
"       $padded   padded, for jsbeeb"
"       $listing   assembly listing"

if ($Run) { & $bem -m3 $ssd }
