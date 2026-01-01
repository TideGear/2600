# =============================================================================
# MECHA SIMULATOR - Makefile
# Atari 2600 (16K F4 Bank-Switching)
# =============================================================================

# Assembler
DASM = dasm

# Flags
# -f3 = output format (3 = raw binary)
# -v4 = verbosity level
# -s  = symbol table output
DASM_FLAGS = -f3 -v4

# Source and output
SRC = mecha.asm
OUT = mecha.bin
SYM = mecha.sym
LST = mecha.lst

# Default target
all: $(OUT)

# Build the ROM
$(OUT): $(SRC) constants.asm ram.asm macros.asm
	$(DASM) $(SRC) $(DASM_FLAGS) -o$(OUT) -s$(SYM) -l$(LST)
	@echo "Build complete: $(OUT)"
	@echo "ROM size:"
	@wc -c < $(OUT) || dir $(OUT)

# Clean build artifacts
clean:
	rm -f $(OUT) $(SYM) $(LST) *.bin *.sym *.lst 2>/dev/null || del /Q $(OUT) $(SYM) $(LST) *.bin *.sym *.lst 2>nul

# Run in Stella emulator (adjust path as needed)
run: $(OUT)
	stella $(OUT)

# Run in Stella with debug mode
debug: $(OUT)
	stella -debug $(OUT)

# Check ROM size
size: $(OUT)
	@echo "ROM size (should be 16384 for 16K):"
	@wc -c < $(OUT) || dir $(OUT)

# Verify ROM is correct size for F4 banking
verify: $(OUT)
	@echo "Verifying ROM..."
	@wc -c < $(OUT) | grep -q "16384" && echo "OK: ROM is 16K" || echo "WARNING: ROM is not 16K"

# Help
help:
	@echo "Mecha Simulator Build System"
	@echo ""
	@echo "Targets:"
	@echo "  all     - Build the ROM (default)"
	@echo "  clean   - Remove build artifacts"
	@echo "  run     - Build and run in Stella"
	@echo "  debug   - Build and run in Stella debug mode"
	@echo "  size    - Show ROM size"
	@echo "  verify  - Verify ROM is correct size"
	@echo "  help    - Show this help"
	@echo ""
	@echo "Requirements:"
	@echo "  - DASM assembler (https://dasm-assembler.github.io/)"
	@echo "  - Stella emulator for testing (optional)"

.PHONY: all clean run debug size verify help

