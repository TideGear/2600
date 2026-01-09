# Atari 2600 Mecha Simulator

This project is a **real Atari 2600** (16K) assembly game that simulates a
first-person mecha cockpit view inspired by *Robot Tank*. It is designed to
assemble with DASM and run on actual 2600 hardware or accurate emulators.

## Core View & Cockpit

- **First-person cockpit view** with a centered crosshair.
- **Heading strip** across the top with N/NE/E/SE/S/SW/W/NW markers.
- **Cockpit UI** at the bottom with a gear selector: `R2, R1, N, 1, 2, 3`.
  - Neutral (`N`) is the starting gear and is boxed.
  - The box moves as gears change.

## Controls

- **Up/Down on joystick**: shift gears.
- **Left/Right on joystick**:
  - Normal: turn the legs (movement direction).
  - **Hold joystick button**: twist the cockpit/torso up to 90° left/right.
- **Button double-tap**: toggle pause.

## Movement & Gearing

- Gears represent forward/backward movement and speed:
  - `R2`, `R1` = reverse (slow/fast).
  - `N` = neutral (no movement).
  - `1`, `2`, `3` = forward speeds.
- **Turning** changes the direction of travel (leg heading). It takes 4 seconds for a full 360 degree turn.
- **Torso twist** changes only the view (cockpit heading), not movement. Torso turning is limited to 90 degrees left or right. Torso turning is twice as fast as leg turning.

### Ground Motion

- The ground is rendered with moving dirt/rock pixels.
- Motion scrolls and shifts based on **leg heading**, while the **camera
  perspective** responds to torso twist for spatial realism.
- Turning is represented by a horizon with mountains and clouds.

### Bobbing & Footfalls

- Gears `R1`, `R2`, `1`, `2`:
  - The view bobs in proportion to speed.
  - Each footfall causes a small screen shake.
  - A stomp sound plays in sync with footfalls.
- Gear `3`:
  - The mech rolls on skates with **no bobbing**.
  - A distinct skate whine replaces stomps.

## Audio

- **Deep engine hum** always present.
  - Pitch increases with forward/backward speed.
  - During pause, the hum stays on at a steady pitch.
- **Stomp sound** for footfalls in walking gears.
- **Skate whine** for gear `3`.

## Tanks & World Model

- The world uses a **16x8 grid** with the player and four enemy tanks.
- The map does **not wrap**: leaving the map starts a visible 10-second countdown.
  - If the countdown reaches 0, the game is lost.
- Tanks **slowly rotate** in place:
  - One full 360° rotation takes ~1 minute.
- Tanks are projected into the cockpit view using:
  - relative position,
  - heading/torso alignment,
  - depth mapping,
  - and directional offsets to mimic rotation.

### LIDAR Detection

- Tanks can scan the player if the mech is within the **front 45° arc** of a tank.
- While scanning:
  - A **red LIDAR bar** fills under the compass.
  - Closer tanks fill the bar faster.
    - Very close tank: ~5 seconds to fill.
    - Far tank (half map): ~60 seconds to fill.
  - Multiple tanks can contribute to the fill rate.
  - The tank flashes red on the pause map while scanning.
- To stop LIDAR scanning:
  - Place the crosshair on the tank to break its lock.
  - That tank is forced to rotate **45° further** before it can detect again.

## Pause Screen

- Double-tap the button to toggle pause.
- Paused view shows:
  - Black background.
  - A **centered 16x8 map**.
  - The player and tanks with facing indicators.
  - Tanks flash red on the map when LIDARing.

## Off-Map Countdown

- Leaving the 16x8 map starts a **10-second countdown**.
- A bar below the compass displays the countdown progress.
- If it reaches 0, the game is lost.