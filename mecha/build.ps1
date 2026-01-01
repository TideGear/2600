# =============================================================================
# MECHA SIMULATOR - PowerShell Build Script
# Atari 2600 (16K F4 Bank-Switching)
# =============================================================================

Write-Host "Building Mecha Simulator..." -ForegroundColor Cyan
Write-Host ""

# Check if DASM is available
$dasm = Get-Command dasm -ErrorAction SilentlyContinue
if (-not $dasm) {
    Write-Host "ERROR: DASM assembler not found in PATH" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please install DASM from: https://dasm-assembler.github.io/"
    Write-Host "Add the DASM directory to your system PATH"
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

# Assemble the ROM
Write-Host "Running DASM assembler..." -ForegroundColor Yellow
& dasm mecha.asm -f3 -v4 -omecha.bin -smecha.sym -lmecha.lst

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "Build successful!" -ForegroundColor Green
    
    # Show file info
    $romFile = Get-Item "mecha.bin" -ErrorAction SilentlyContinue
    if ($romFile) {
        Write-Host "Output: mecha.bin"
        Write-Host "ROM size: $($romFile.Length) bytes"
        
        # Verify size for 16K
        if ($romFile.Length -eq 16384) {
            Write-Host "Size OK: Correct 16K ROM" -ForegroundColor Green
        } elseif ($romFile.Length -eq 4096) {
            Write-Host "Note: ROM is 4K (single bank)" -ForegroundColor Yellow
        } else {
            Write-Host "Warning: Unexpected ROM size" -ForegroundColor Yellow
        }
    }
    
    Write-Host ""
    
    # Check for Stella
    $stella = Get-Command stella -ErrorAction SilentlyContinue
    if ($stella) {
        Write-Host "Stella emulator found. Run 'stella mecha.bin' to test."
    } else {
        Write-Host "To test, open mecha.bin in Stella or another Atari 2600 emulator."
        Write-Host "Download Stella: https://stella-emu.github.io/"
    }
} else {
    Write-Host ""
    Write-Host "Build FAILED! Check the errors above." -ForegroundColor Red
}

Write-Host ""
Read-Host "Press Enter to exit"

