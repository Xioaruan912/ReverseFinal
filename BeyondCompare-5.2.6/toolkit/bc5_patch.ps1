# =============================================================================
#  Beyond Compare 5.2.6.32774 - offline licence patch (portable PowerShell)
#
#  Patches an already installed BCompare.exe in place.  Same patch table as
#  toolkit/bc5_patch.py; the result is verified against the golden hash.
#
#  Usage:
#     $env:BC_EXE = 'C:\path	o\BCompare.exe'
#     powershell -NoProfile -ExecutionPolicy Bypass -File bc5_patch.ps1
# =============================================================================

$ErrorActionPreference = 'Stop'

$ORIG_SHA256  = '4e44c526722d6420e89b372460c519e293c417723305b83ed0eff853db16ce5d'
$ORIG_SIZE    = 50565160
$GOLD_SHA256  = 'aba327b822ae74d896c53ccfbe1ae57cc40e46350e929634cd5631d80e0d66dc'

function Invoke-Patch([string]$file) {
  $bytes = [IO.File]::ReadAllBytes($file)
  if ($bytes.Length -ne $ORIG_SIZE) {
    Die ('unexpected size ' + $bytes.Length + ' (expected ' + $ORIG_SIZE + ') - wrong build?')
  }
  if ((Get-Sha256 $file) -ne $ORIG_SHA256) {
    Die 'installed BCompare.exe does not match the pinned build - aborting'
  }

  foreach ($p in $CODE_PATCHES) {
    $old = Convert-HexToBytes $p.old
    $new = Convert-HexToBytes $p.new
    $cur = New-Object byte[] $old.Length
    [Array]::Copy($bytes, $p.off, $cur, 0, $old.Length)
    for ($i = 0; $i -lt $old.Length; $i++) {
      if ($cur[$i] -ne $old[$i]) { Die ('patch site 0x{0:x} does not match the pinned build' -f $p.off) }
    }
    [Array]::Copy($new, 0, $bytes, $p.off, $new.Length)
  }
  Ok ('applied ' + $CODE_PATCHES.Count + ' code patches')

  foreach ($p in $STR_PATCHES) {
    $old = [Text.Encoding]::ASCII.GetBytes($p.old)
    $new = [Text.Encoding]::ASCII.GetBytes($p.new)
    if ($new.Length -ne $old.Length) { Die 'string patch length mismatch' }
    $cur = New-Object byte[] $old.Length
    [Array]::Copy($bytes, $p.off, $cur, 0, $old.Length)
    for ($i = 0; $i -lt $old.Length; $i++) {
      if ($cur[$i] -ne $old[$i]) { Die ('string site 0x{0:x} does not match the pinned build' -f $p.off) }
    }
    [Array]::Copy($new, 0, $bytes, $p.off, $new.Length)
  }
  Ok ('applied ' + $STR_PATCHES.Count + ' upstream-detachment patches')

  # drop the Authenticode certificate table: Beyond Compare verifies its own
  # signature at start-up and refuses to run once the image has been changed
  $lfanew = [BitConverter]::ToUInt32($bytes, 0x3c)
  $dd     = [int]$lfanew + 24 + 112 + 32          # data directory #4 = Security
  $secOff = [BitConverter]::ToUInt32($bytes, $dd)
  $secSz  = [BitConverter]::ToUInt32($bytes, $dd + 4)
  if ($secOff -gt 0) {
    if (($secOff + $secSz) -ne $bytes.Length) { Die 'unexpected certificate layout' }
    $trimmed = New-Object byte[] $secOff
    [Array]::Copy($bytes, 0, $trimmed, 0, $secOff)
    $bytes = $trimmed
    for ($i = 0; $i -lt 8; $i++) { $bytes[$dd + $i] = 0 }
    Ok ('removed certificate table (' + $secSz + ' bytes) - self-signature check disabled')
  }

  [IO.File]::WriteAllBytes($file, $bytes)

  $h = Get-Sha256 $file
  if ($h -ne $GOLD_SHA256) {
    Die ('result does not match the golden hash' + [Environment]::NewLine + '        got ' + $h)
  }
  Ok ('golden hash verified: ' + $h)
}

function Convert-HexToBytes([string]$hex) {
  $out = New-Object byte[] ($hex.Length / 2)
  for ($i = 0; $i -lt $out.Length; $i++) { $out[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16) }
  return $out
}
function Get-Sha256($path) {
  return (Get-FileHash -Path $path -Algorithm SHA256).Hash.ToLower()
}

$Auto = ($env:BC_YES -eq '1')

$CODE_PATCHES = @(
  # licence state machine: force the "registered" terminal state
  @{ off = 0x04f286e; old = '8b85f0030000'; new = 'b86b00000090' },
  # property getters
  @{ off = 0x04f5560; old = '480fb68110060000c3'; new = 'b003c3cccccccccccc' },
  @{ off = 0x04f5570; old = '480fb68111060000c3'; new = 'b007c3cccccccccccc' },
  @{ off = 0x04f5580; old = '480fb68162010000c3'; new = 'b000c3cccccccccccc' },
  @{ off = 0x04f55f0; old = '480fb68130060000c3'; new = 'b001c3cccccccccccc' },
  @{ off = 0x021b110; old = '480fb681f8060000c3'; new = 'b001c3cccccccccccc' },
  # CheckForUpdatesExecute -> immediate ret
  @{ off = 0x0fa9950; old = '4883ec28488b0d85c5f7ffe870a2f3ff4883c428c3'; new = ('c3' + ('cc' * 20)) },
  # crash guards for the registered path (nil certificate string)
  @{ off = 0x0da1a3e; old = '480fb618'; new = 'b3049090' },
  @{ off = 0x0da1c12; old = '480fb600'; new = 'b0049090' },
  @{ off = 0x0da1c93; old = '480fb600'; new = 'b0049090' }
)
$STR_PATCHES = @(
  # same-length replacements (fixed-length strings inside a compiled DFM blob)
  @{ off = 0x2ff1aa5; old = 'https://www.scootersoftware.com/bugRepMailer.php'; new = 'https://127.0.0.1.invalid/bugRepMailer.php//////' },
  @{ off = 0x2ff1c32; old = 'crash@scootersoftware.com'; new = 'crash@127.0.0.1.invalid..' }
)


# --------------------------------------------------------------------- main
function Ok($m)   { Write-Host ('  [ok]   ' + $m) -ForegroundColor Green }
function Warn($m) { Write-Host ('  [!]    ' + $m) -ForegroundColor Yellow }
function Die($m)  { Write-Host ('  [x]    ' + $m) -ForegroundColor Red; exit 1 }

$exe = $env:BC_EXE
if (-not $exe) {
  $guess = Join-Path ([Environment]::GetFolderPath('Desktop')) 'BeyondCompare-5.2.6\BCompare.exe'
  if (Test-Path $guess) { $exe = $guess }
}
if (-not $exe) { Die 'set BC_EXE to the BCompare.exe you want to patch' }
if (-not (Test-Path $exe)) { Die ('not found: ' + $exe) }

Write-Host ''
Write-Host ('Beyond Compare whitespace patch -> ' + $exe) -ForegroundColor White
if ((Get-Sha256 $exe) -eq $GOLD_SHA256) { Ok 'already patched'; exit 0 }
Invoke-Patch $exe
Write-Host ''
Write-Host 'done - run BCompare.exe, the evaluation banner is gone.' -ForegroundColor Green
