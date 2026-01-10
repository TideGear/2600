# 
# Build script for the Atari 2600 Mecha Simulator.
#
# What it does:
# - Regenerates playfield lookup tables into `src/include/generated_tables.inc`
#   (these are used by the cycle-stable visible kernel).
# - Assembles `src/mecha.asm` with DASM into a 16K (F6) ROM at `build/mecha.bin`.
# - Produces a listing (`.lst`) and symbols (`.sym`) which are useful in Stella.
#
# Requirements:
# - `python` available in PATH
# - `dasm` available in PATH
#
# Usage (from repo root):
#   .\tools\build.ps1
#
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$src  = Join-Path $root "src\\mecha.asm"
$outDir = Join-Path $root "build"

New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$outBin = Join-Path $outDir "mecha.bin"
$outLst = Join-Path $outDir "mecha.lst"
$outSym = Join-Path $outDir "mecha.sym"

Write-Host "Generating tables..."
& python (Join-Path $root "tools\\gen_tables.py")
if ($LASTEXITCODE -ne 0) {
  throw "Table generation failed with exit code $LASTEXITCODE"
}

Write-Host "Assembling $src -> $outBin"

& dasm $src `
  -f3 `
  ("-o{0}" -f $outBin) `
  ("-l{0}" -f $outLst) `
  ("-s{0}" -f $outSym) `
  ("-I{0}" -f (Join-Path $root "src\\include"))

if ($LASTEXITCODE -ne 0) {
  throw "DASM failed with exit code $LASTEXITCODE"
}

Write-Host "OK"

