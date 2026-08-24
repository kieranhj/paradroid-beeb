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

# The briefing text is hand-editable (src/data/briefing.txt) and converted
# every build - the one exporter build.ps1 DOES run, because its input is a
# checked working file rather than the C64 listing. See tools/make_briefing.py.
python (Join-Path $root 'tools\make_briefing.py')
if ($LASTEXITCODE -ne 0) { throw "make_briefing failed ($LASTEXITCODE)" }

# The OTHER exporters are not run here, because their input is the C64 listing
# and that is supplied locally rather than checked in. That is fine for a code
# change and a trap for a DATA one: tools/deck_palettes.json is hand-edited in
# palette_lab.py, and a build after editing it silently used the old
# src/data/colours.asm - the palettes and the text-screen backgrounds simply
# did not appear, with nothing to say why. Caught 2026-08-24. Stop instead.
$palJson = Join-Path $root 'tools\deck_palettes.json'
$palAsm  = Join-Path $root 'src\data\colours.asm'
if ((Test-Path $palJson) -and (Test-Path $palAsm)) {
    $j = (Get-Item $palJson).LastWriteTimeUtc
    $a = (Get-Item $palAsm).LastWriteTimeUtc
    if ($j -gt $a) {
        throw ("deck_palettes.json is newer than src/data/colours.asm, so this " +
               "build would use the OLD palettes. Run:`n" +
               "    python tools\export_bbc.py")
    }
}

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
