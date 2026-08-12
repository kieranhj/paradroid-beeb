# Build Paradroid -> PARADROID.SSD, or PARADROID-M.SSD for the Master
#
# TARGET_MASTER in src\main.asm is the single source of truth for which
# machine is being built; this script only reads it, so the two images
# never get mixed up. -BemModel picks b-em's model number for -Run: 3 is
# the Model B, and the Master's number depends on the b-em build, so pass
# it explicitly rather than have this guess.
param([switch]$Run, [int]$BemModel = 3)

$ErrorActionPreference = 'Stop'
$root    = $PSScriptRoot
$beebasm = Join-Path $root 'bin\beebasm.exe'
$bem     = 'C:\Users\khcon\OneDrive\BEEB\B-Em\b-em-42f6597-w64\b-em.exe'

$main = Join-Path $root 'src\main.asm'
$isMaster = [bool](Select-String -Path $main -Pattern '^\s*TARGET_MASTER\s*=\s*TRUE\b' -Quiet)
if ($isMaster) { $ssd = Join-Path $root 'PARADROID-M.SSD' }
else           { $ssd = Join-Path $root 'PARADROID.SSD' }

# -dd -labels writes every global and local symbol with its address, which
# is what turns an emulator poke into something aimed rather than guessed.
$labels = [IO.Path]::ChangeExtension($ssd, '.labels')

& $beebasm -i $main -do $ssd -boot PARA -v -dd -labels $labels
if ($LASTEXITCODE -ne 0) { throw "beebasm failed ($LASTEXITCODE)" }
if ($isMaster) { "Built $ssd  (Master 128, 2 px scroll)" } else { "Built $ssd" }

if ($Run) {
  if ($isMaster -and -not $PSBoundParameters.ContainsKey('BemModel')) {
    "Master build: pass -BemModel <n> for b-em's Master model, or pick it in b-em."
  }
  & $bem "-m$BemModel" $ssd
}
