# Build Paradroid (BBC Model B) -> build/paradroid.ssd
# -Intro additionally assembles pdloader/paradroid_intro.asm (scarybeasts'
# loading intro and its sample player, docs/intro.md) and wires "*RUN PINTRO"
# into !BOOT behind PARSWR; the default build carries no trace of it.
# -Release is the build for other people: -Intro, plus every DEBUG_ flag
# forced off. It is the only build a player should ever see.
param([switch]$Run, [switch]$Intro, [switch]$Release)

$ErrorActionPreference = 'Stop'
if ($Release) { $Intro = $true }
# RELEASE is a command-line symbol because beebasm has no IFDEF and refuses a
# symbol defined twice, so main.asm cannot carry a default of its own. It is
# passed on EVERY build, and a bare beebasm invocation has to pass it too -
# the symbol dump in CLAUDE.md does. main.asm's DEV is what the flags read.
$relDef = if ($Release) { 'RELEASE=1' } else { 'RELEASE=0' }
# 2 = *RUN !BOOT (the RELEASE stub), 3 = *EXEC !BOOT (the dev text file)
$bootOpt = if ($Release) { 2 } else { 3 }
# The interpreter and the two binaries are overridable, so that the
# Makefile (issue #3) can hand this script the same tools it is using and
# `make check-ps1` can prove the two builds agree. Unset, everything is
# exactly what it always was: `python` and the checked-out bin/.
$python  = if ($env:PYTHON)  { $env:PYTHON }  else { 'python' }
$root    = $PSScriptRoot
$beebasm = if ($env:BEEBASM) { $env:BEEBASM }
           else { Join-Path $root ('bin' + [IO.Path]::DirectorySeparatorChar + 'beebasm.exe') }
$build   = Join-Path $root 'build'
$raw     = Join-Path $build 'paradroid-raw.ssd'
$ssd     = Join-Path $build 'paradroid.ssd'
$padded  = Join-Path $build 'paradroid-200k.ssd'
$listing = Join-Path $build 'paradroid.lst'
# -Run's emulator: $env:EMU, as the Makefile's EMU= - a b-em, since -Run
# passes b-em's flags. Unset, it is the one on KC's machine.
$bem     = if ($env:EMU) { $env:EMU }
           else { 'C:\Users\khcon\OneDrive\BEEB\B-Em\b-em-42f6597-w64\b-em.exe' }

if (-not (Test-Path $build)) { New-Item -ItemType Directory -Path $build | Out-Null }

# The briefing text is hand-editable (src/data/briefing.txt) and converted
# every build - the one exporter build.ps1 DOES run, because its input is a
# checked working file rather than the C64 listing. See tools/make_briefing.py.
& $python (Join-Path $root 'tools\make_briefing.py')
if ($LASTEXITCODE -ne 0) { throw "make_briefing failed ($LASTEXITCODE)" }

# The OTHER exporters are not run here, because their input is the C64 listing
# and their output, src/data/, is committed (`make data` regenerates it; the
# listing itself is committed since 2026-09-09). That is fine for a code
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
# THE DISC OPTION FOLLOWS THE !BOOT SHAPE (issue #18 item 4): -opt 3
# *EXECs the text !BOOT a dev build assembles, -opt 2 *RUNs the 6502
# stub a RELEASE build assembles instead (main.asm, BOOT_RUN), which
# needs no language ROM. main.asm assembles its own !BOOT either way
# (with the build timestamp) rather than using -boot, and make_disc.py
# carries the raw image's option through to the disc it writes.
#
# THE PACK LOOP. beebasm cannot compress its own output, and two of the
# things bank 6 carries are assembled code copied down to run elsewhere -
# the PARBRF driver and the low overlay. main.asm SAVEs each block under an
# X-name; tools/pack_overlays.py reads those back out, ZX0s them and writes
# src/data/brfimg.asm and lowimg.asm for the NEXT assembly to INCLUDE. It
# exits 10 when it rewrote one, so the loop assembles again - a stream that
# changed SIZE has moved the bank around under the very block it came from.
# IN THE STEADY STATE THIS IS ONE ASSEMBLY: the first pass extracts what is
# already there, finds it unchanged and exits 0.
& $python (Join-Path $root 'tools\pack_overlays.py') --ensure $raw
if ($LASTEXITCODE -ne 0) { throw "pack_overlays --ensure failed ($LASTEXITCODE)" }
$packed = $false
for ($pass = 1; $pass -le 4; $pass++) {
    & $beebasm -i (Join-Path $root 'src\main.asm') -do $raw -opt $bootOpt -title PARADROID -D $relDef -v |
        Out-File -FilePath $listing -Encoding utf8
    if ($LASTEXITCODE -ne 0) { throw "beebasm failed ($LASTEXITCODE)" }

    & $python (Join-Path $root 'tools\pack_overlays.py') $raw
    $rc = $LASTEXITCODE
    if ($rc -eq 0) { $packed = $true; break }
    if ($rc -ne 10) { throw "pack_overlays failed ($rc)" }
}
if (-not $packed) {
    throw "pack_overlays did not settle in 4 passes - the overlays' own bytes depend on the bank layout their size decides"
}

# -Intro: a second beebasm pass over scarybeasts' intro, which brings its own
# SAVE and eleven PUTFILEs. IT MUST RUN FROM pdloader/: those PUTFILE paths are
# relative to the working directory, and from the project root they resolve to
# nothing, leaving a disc with PINTRO on it and none of its samples.
$introRaw = $null
if ($Intro) {
    # The intro's data is generated: one ZX0 stream for the whole 16K sideways
    # image and one for the 20K screen, 33,912 bytes of loose files down to
    # 5,451. Unlike the other exporters this one IS run here - its input is
    # pdloader's own checked-in binaries, not the C64 listing.
    & $python (Join-Path $root 'tools\make_intro_data.py')
    if ($LASTEXITCODE -ne 0) { throw "make_intro_data failed ($LASTEXITCODE)" }

    $introRaw = Join-Path $build 'pintro-raw.ssd'
    Push-Location (Join-Path $root 'pdloader')
    try {
        & $beebasm -i 'paradroid_intro.asm' -do $introRaw -opt 0
        if ($LASTEXITCODE -ne 0) {
            throw "beebasm failed on paradroid_intro.asm ($LASTEXITCODE)"
        }
    } finally { Pop-Location }
}

# Post-process: ZX0-compress the four bank files, lay the disc out in boot
# access order, and write the padded copy jsbeeb needs (it will not boot an
# unpadded image - beebasm's ends mid-track and the DFS FDC poll hangs).
# THE RAW IMAGE IS NOT BOOTABLE: the loader expects compressed streams at
# DEPK_STREAM. Never hand $raw to an emulator. See tools/make_disc.py.
$discArgs = @($raw, $ssd, $padded)
if ($introRaw) { $discArgs += @('--intro', $introRaw) }
& $python (Join-Path $root 'tools\make_disc.py') @discArgs
if ($LASTEXITCODE -ne 0) { throw "make_disc failed ($LASTEXITCODE)" }

if ($Release) { "RELEASE build: intro on, every DEBUG_ flag off" }
"Built  $ssd"
"       $padded   padded, for jsbeeb"
"       $listing   assembly listing"

# -m10 is the Master 128 on a stock b-em.cfg, which has the four sideways
# RAM banks; -m3 was a B with a standard ROM setup. hexwab, issue #3.
if ($Run) { & $bem -m10 -autoboot -disc $ssd }
