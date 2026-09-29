# Super Off-Road - MiSTer FPGA Core

A from-scratch MiSTer FPGA re-implementation of Leland/Tradewest's **Super
Off-Road** (1989): twin Z80 master/slave boards, custom tile/sprite video,
and the real Leland 80186-based sound board, all reproduced in RTL rather
than emulated at the instruction level. The same bitstream also runs
**Super Off-Road Track-Pak** and **Pig Out: Dine Like a Swine!**.

## Supported games

| Game | MAME set | MRA |
|---|---|---|
| Ironman Ivan Stewart's Super Off-Road (rev 4) | `offroad` | `Ironman Ivan Stewart's Super Off-Road (rev 4).mra` |
| Ironman Ivan Stewart's Super Off-Road Track-Pak (rev 4) | `offroadt` | `Ironman Ivan Stewart's Super Off-Road Track-Pak (rev 4).mra` |
| Pig Out: Dine Like a Swine! (rev 2) | `pigout` | `Pig Out Dine Like a Swine! (rev 2).mra` |

The board is not generic across the whole Leland catalog; these are the
games verified so far.

This core was developed by studying MAME's Leland drivers and the game
ROMs. It has not been verified against an original PCB, so expect small
differences from real hardware in edge cases.

## Video

The core outputs standard video via the MiSTer scaler, and can also drive
a CRT (15 kHz RGB or Y/C) directly.

| OSD option | Effect |
|---|---|
| **Aspect ratio** | Original, Full Screen or a custom ratio |
| **Video Timing** | **CRT 60Hz** (default): a DDR3 frame buffer regenerates the picture as NTSC-standard 240p (15.73 kHz / 60.03 Hz) while the game keeps running at its native 65.95 Hz. **Native 66Hz**: the game's own timing is passed straight through. |
| **CRT V Position** | Shifts the picture up or down (CRT 60Hz timing only) |
| **CRT V Size** | Scales the 240-line picture down to 236...208 lines with a photometric (linear-light) vertical blend, for CRTs that overscan the top and bottom (CRT 60Hz timing only) |

## Controls

The cabinet has a free-spinning steering wheel and a gas pedal per player.
Three steering inputs are combined automatically, so you can mix them:

| Input | Behavior |
|---|---|
| **Spinner** | Direct 1:1 mapping, like the original cabinet |
| **Analog stick** | Deflection sets the turn rate |
| **Digital d-pad** | Left/Right steer. **D-Pad Steering** selects **Velocity** (default; ramps a turn rate and coasts back to straight) or **Position** (a virtual spring-centered stick) |

Buttons (`Nitro, Coin, Gas, Start`):

| Button | Super Off-Road / Track-Pak | Pig Out |
|---|---|---|
| 1 | Nitro | Button 1 (Jump) |
| 2 | Coin | Button 2 (Throw) |
| 3 | Gas (digital: 0 or full; MiSTer has no analog trigger support) | Start |
| 4 | Menu Enter (see Service menu) | Coin |

## Service menu

The game's operator menu is opened from the OSD with **Service Menu**; it
presses the Test switch for you (plus Start for Pig Out). Inside the
Super Off-Road menus, **Menu Enter** acts as Blue Nitro (P3's Nitro), so a
single controller can select (Nitro) and enter (Menu Enter). Lives and
difficulty are set there; the hardware has no DIP switches.

## Building

Requires **Quartus Prime 17.0.x** (Lite or Standard). The Z80 core is a git
submodule, so clone with submodules:

```sh
git clone --recurse-submodules <repo-url>
quartus_sh --flow compile SuperOffRoad
```

This produces `output_files/SuperOffRoad.rbf`.

## Installing on MiSTer

Copy to your MiSTer:

- `releases/Arcade-SuperOffRoad_<date>.rbf` (or your own build) to `/media/fat/_Arcade/cores/`
- The MRA for each game you want, from `releases/`, to `/media/fat/_Arcade/`

You need the matching MAME ROM set for each game (`offroad`, `offroadt` or
`pigout`). This repo does not include or distribute any ROM data.

The MRAs load the ROMs through DDR3 (`address="0x30000000"`), which makes
loading much faster than the per-byte download.

## Simulation

`sim/` has standalone ModelSim and Verilator testbenches for the SDRAM
controller, the sound board and the full board (the real Z80 cores booting
against the real ROMs). See `sim/README.md` for the commands.

## Credits / third-party sources

- **MAME's `leland.cpp` / `leland_m.cpp` / `leland_v.cpp` / `leland_a.cpp`**:
  studied as the primary documentation of the Leland board's behavior (not
  redistributed here).
- [`tv80`](https://github.com/hutch31/tv80): synthesizable Z80 core (MIT), as a submodule in `rtl/tv80`.
- [`jamieiles/80x86`](rtl/s80x86/README_VENDORING.md): vendored 8086/80186
  core for the sound-board CPU (GPLv3).
- [`KF8253`](rtl/KF8253/README_UPSTREAM.md): 8253 PIT core for the sound
  board.
- `rtl/sdram.sv` and `rtl/sdram_banked.sv`: SDRAM controllers, MIT licensed
  (Kevin Coleman).
- The [MiSTer framework](https://github.com/MiSTer-devel) (`sys/`).

## License

GNU GPL v3 or later (see `LICENSE`). The vendored and third-party components
above keep their own licenses.
