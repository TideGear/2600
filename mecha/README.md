# MECHA SIMULATOR

An Atari 2600 assembly game featuring a first-person mecha cockpit view inspired by *Star Raiders*.

## Features

- **First-person cockpit view** with centered crosshair
- **Compass heading strip** showing N/NE/E/SE/S/SW/W/NW
- **6-speed transmission**: R2, R1, N, 1, 2, 3
- **Independent leg/torso control**: Move in one direction, look in another
- **4 enemy tanks** on a 32×32 world grid
- **LIDAR detection system** with warning bar
- **View bobbing** for walking gears, smooth skating in gear 3
- **Engine audio** that changes pitch with speed
- **Pause screen** with tactical map

## Controls

| Input | Action |
|-------|--------|
| Joystick Up | Shift gear up |
| Joystick Down | Shift gear down |
| Joystick Left/Right | Turn legs (movement direction) |
| Button + Left/Right | Twist torso (view direction) |
| Double-tap Button | Toggle pause |

## Gears

| Gear | Speed | Effect |
|------|-------|--------|
| R2 | Fast reverse | Walking with heavy bob |
| R1 | Slow reverse | Walking with light bob |
| N | Neutral | Stationary |
| 1 | Slow forward | Walking with light bob |
| 2 | Medium forward | Walking with medium bob |
| 3 | Fast forward | Skating (no bob, whine sound) |

## Building

### Requirements

- **DASM Assembler**: Download from [dasm-assembler.github.io](https://dasm-assembler.github.io/)
- Add DASM to your system PATH

### Build Commands

**Windows (Command Prompt):**
```batch
build.bat
```

**Windows (PowerShell):**
```powershell
.\build.ps1
```

**Linux/macOS:**
```bash
make
```

**Manual build:**
```bash
dasm mecha.asm -f3 -omecha.bin
```

### Output

- `mecha.bin` - The ROM file (4K initially, expandable to 16K)
- `mecha.sym` - Symbol table for debugging
- `mecha.lst` - Assembly listing

## Testing

### Recommended Emulator

**Stella** - The most accurate Atari 2600 emulator
- Download: [stella-emu.github.io](https://stella-emu.github.io/)
- Run: `stella mecha.bin`

### Debug Mode

In Stella, press \` (backtick) to open the debugger for:
- Memory inspection
- Breakpoints
- Step-through execution
- TIA/RIOT register viewing

## Technical Details

### Memory Map

- **ROM**: $F000-$FFFF (4K, expandable to 16K with F4 banking)
- **RAM**: $80-$FF (128 bytes)
- **TIA**: $00-$3F (video/audio hardware)
- **RIOT**: $280-$297 (I/O and timer)

### Display Zones

| Zone | Scanlines | Content |
|------|-----------|---------|
| Compass | 10 | Heading indicator strip |
| Status Bars | 6 | LIDAR and countdown bars |
| Main View | 140 | 3D cockpit view with crosshair |
| Cockpit UI | 36 | Gear selector display |
| **Total** | 192 | |

### RAM Usage

| Variable | Bytes | Purpose |
|----------|-------|---------|
| Player state | 6 | Position, heading, torso offset |
| Tank states | 20 | 4 tanks × 5 bytes each |
| Game state | 10 | Gear, LIDAR, countdown, etc. |
| Input state | 6 | Joystick, button, debounce |
| Audio state | 4 | Engine pitch, stomp timer |
| Rendering | 24 | Temp variables, buffers |
| **Total** | ~70 | ~58 bytes free for expansion |

## Project Structure

```
mecha/
├── mecha.asm           # Main source file
├── constants.asm       # Hardware registers & game constants
├── ram.asm            # RAM variable definitions
├── macros.asm         # Assembly macros
├── bank1_graphics.asm # Sprite and font data (expansion)
├── bank2_logic.asm    # Math tables and AI (expansion)
├── bank3_expansion.asm# Reserved for future features
├── build.bat          # Windows build script
├── build.ps1          # PowerShell build script
├── Makefile           # Unix build script
└── README.md          # This file
```

## Expansion Roadmap

The 16K ROM architecture leaves room for:

- [ ] **Weapons system** - Fire at tanks
- [ ] **Tank destruction** - Win condition
- [ ] **Terrain types** - Different ground textures
- [ ] **Power-ups** - Speed boost, shields
- [ ] **More enemy types** - Scouts, heavy tanks
- [ ] **Mission objectives** - Survive, destroy all, escape

## License

This project is provided as-is for educational purposes. Feel free to modify and learn from the code.

## Acknowledgments

- Inspired by *Star Raiders* (Atari, 1979)
- Built for the Atari 2600 hardware specifications
- DASM assembler by Matthew Dillon and contributors

