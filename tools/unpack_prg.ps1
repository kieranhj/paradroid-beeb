<#
.SYNOPSIS
    Unpack a cracked/compressed C64 .prg to a flat 64K RAM image, by running it.

.DESCRIPTION
    The Paradroid .prg files in prgs/ are all cracked and packed, so diffing them
    directly is worthless - a signature sweep of the listing's data blocks finds
    at most 3 of 11 probes in any of them. Diffing the *unpacked* RAM images is
    trivial by comparison, and that is what this script produces.

    It boots x64sc with a monitor command file that installs a non-stopping
    checkpoint on writes to $D015 (the VIC sprite-enable register, touched every
    frame once the game is running) and saves all of RAM each time it fires. The
    file is rewritten continuously, so killing the emulator after N seconds
    leaves the most recent state on disc.

    Three details matter and each cost a debugging cycle to find:

      * `trace`, not `break`. A `break` checkpoint halts in the monitor and the
        emulator stops dead; `trace` runs the attached command and carries on.
      * `bank ram`, or `save` dumps the CPU's view - KERNAL ROM at $E000-$FFFF
        and I/O at $D000-$DFFF instead of the game's code.
      * The KERNAL's reset-time VIC clear writes $D015 before the program has
        loaded. With `break` + a hit count this has to be skipped explicitly;
        with `trace` it is simply overwritten by every later frame.

    COMPARE LIKE WITH LIKE. The dump captures whatever state the game happens to
    be in, and Paradroid passes through three of them:

      1. depacked, title screen - the staging block at $8000-$BFFF holds the
         high code, and $C000-$FFFF is still zero;
      2. in game, early - the high code has been copied up to $C000-$FFFF and
         the staging block is still intact, so both copies are present;
      3. in game, later - the staging block has been overwritten with filler
         and only the $C000-$FFFF copy remains.

    So $8000-$BFFF is *not* durable, and neither is a naive whole-image diff.
    $1000-$3FFF (core code) and, once past state 1, $C000-$FFFF are stable: two
    dumps of the original taken in states 2 and 3 agree 100% across both. Pick
    the region to diff by which state both dumps reached, and check that they
    reached the same one before believing any result.

.PARAMETER Prg
    Path to the .prg to unpack.

.PARAMETER Out
    Path to write the RAM image to. VICE prepends a 2-byte load address, so the
    file is 65538 bytes and byte $0000 of RAM is at offset 2.

.PARAMETER Seconds
    Wall-clock time to let it run before killing the emulator. This is NOT C64
    time: saving 64K on every frame throttles the emulator heavily. The default
    of 30 reliably reaches a depacked state. The script verifies that and fails
    loudly otherwise, so if it throws, raise this rather than trusting the file.
    Which of the three states above you land in is a race, so re-run and check
    if you need a particular one; press fire in the window to reach state 2/3.

.PARAMETER Vice
    Path to x64sc.exe.

.EXAMPLE
    .\tools\unpack_prg.ps1 -Prg '.\prgs\Paradroid (1985)(Graftgold).prg' -Out .\orig.bin

.EXAMPLE
    # unpack all four, then diff in Python: bytes[2:] is RAM $0000-$FFFF
    Get-ChildItem .\prgs\*.prg | ForEach-Object {
        .\tools\unpack_prg.ps1 -Prg $_.FullName -Out ".\dumps\$($_.BaseName).bin"
    }
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Prg,
    [Parameter(Mandatory)] [string] $Out,
    [int]    $Seconds = 30,
    [string] $Vice    = 'C:\Users\khcon\OneDrive\Commodore\WinVICE-3.1-x64\x64sc.exe'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Prg))  { throw "No such .prg: $Prg" }
if (-not (Test-Path $Vice)) { throw "x64sc.exe not found at $Vice - pass -Vice" }

# Resolve before launching. VICE runs with its working directory set to the
# output folder (see below), so a relative -Prg would silently fail to load and
# the dump would be nothing but VICE's power-on RAM pattern.
$Prg = (Resolve-Path $Prg).Path

$outFull = [System.IO.Path]::GetFullPath($Out)
$outDir  = Split-Path $outFull -Parent
$outName = Split-Path $outFull -Leaf
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
if (Test-Path $outFull) { Remove-Item $outFull }

# The monitor saves relative to VICE's working directory, so run it in $outDir
# and refer to the dump by bare filename - it avoids having to escape a Windows
# path inside an already-escaped monitor command string.
$mon = Join-Path ([System.IO.Path]::GetTempPath()) ("unpack_{0}.txt" -f [System.IO.Path]::GetRandomFileName())
Set-Content -Path $mon -Encoding ascii -Value @(
    'bank ram'
    'trace store d015'
    ('command 1 "save \"{0}\" 0 0000 ffff"' -f $outName)
)

try {
    $p = Start-Process -FilePath $Vice -WorkingDirectory $outDir -PassThru `
         -ArgumentList @('-moncommands', $mon, '-autostart', "`"$Prg`"")
    Start-Sleep -Seconds $Seconds
    if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
}
finally {
    Remove-Item $mon -ErrorAction SilentlyContinue
}

if (-not (Test-Path $outFull)) {
    throw "No dump produced. The checkpoint never fired - the program may not have autostarted."
}

# Sanity-check that the depack actually finished. This is worth doing properly:
# a dump taken mid-load, or one where the .prg never autostarted at all, looks
# superficially plausible - tens of thousands of non-zero bytes - and silently
# diffing such an image wastes an afternoon.
#
# Counting non-zero bytes does NOT distinguish the two, because VICE initialises
# RAM to a fixed pattern of alternating $00 and $FF blocks, which is ~50% non-zero
# to begin with. Counting DISTINCT byte values does: the pattern has exactly two,
# real 6502 code has most of the 256. $1000-$3FFF is the region to test - it holds
# core code in every release and, unlike $8000-$BFFF, it is not overwritten as the
# game runs.
$bytes = [System.IO.File]::ReadAllBytes($outFull)
$seen  = New-Object bool[] 256
for ($i = 2 + 0x1000; $i -lt 2 + 0x4000; $i++) { $seen[$bytes[$i]] = $true }
$distinct = @($seen | Where-Object { $_ }).Count
if ($distinct -lt 64) {
    throw ("Dump is not a depacked game - only $distinct distinct byte values in " +
           "`$1000-`$3FFF (bare power-on RAM has 2, real code has 200+). Either the " +
           ".prg never autostarted - check the path - or the depack had not finished, " +
           "in which case re-run with a larger -Seconds.")
}

Write-Host ("{0}  ({1} bytes; RAM `$0000 is at offset 2; {2} distinct byte values in `$1000-`$3FFF)" `
            -f $outFull, $bytes.Length, $distinct)
