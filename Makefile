ROM=mecha.bin
ASM=mecha.asm

all: $(ROM)

$(ROM): $(ASM)
	dasm $(ASM) -f3 -o$(ROM)

clean:
	rm -f $(ROM) *.lst *.sym
