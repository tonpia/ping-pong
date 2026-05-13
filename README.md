# OV7670 → VGA Real-Time Filter Pipeline

A baseline real-time camera-to-display pipeline for the **Digilent Basys 3 (Artix-7)** FPGA. It captures live frames from an **OV7670** camera module, stores them in on-chip block RAM, applies one of several switch-selectable image filters, and drives a **640×480 @ 60 Hz VGA** monitor.

| | |
|---|---|
| Target board | Digilent Basys 3 |
| Camera | OV7670 (Pmod JB), RGB565 @ 320×240 sub-sampled |
| Display | VGA 640×480 @ 60 Hz (320×240 pixel-doubled) |
| Toolchain | Vivado (project under [src/](src/)) |
| Sim | cocotb + Icarus Verilog (under [testbench/](testbench/)) |

---

## Top-level data flow

```
                                ┌────────────────┐
   clk100 ──► clk_wiz_0 ────────┤ clk50  (debounce)
                                ├ clk25  (VGA + SCCB)
                                ├ clk24  (OV7670 XCLK)
                                └────────────────┘

   btn ─► debounce ─► I2C_AV_Config (SCCB) ─► OV7670_SIOC / SIOD
                          │
                          └─► I2C_Controller + RGB565 register LUT
                              (soft-reset 0x12=0x80 first, then full LUT;
                               40 ms start-up gate before any SCCB)

   OV7670_PCLK ─► BUFG ─► pclk (global clock network)
                            │
   HREF / VSYNC / D[7:0] ───┘
        │
        ▼
   ov7670_capture  ──(RGB565 → RGB444, addr = y*320+x, we)──►  blk_mem_gen_0
                                                                 │  (dual-port BRAM)
                                                                 ▼
                                                      raw_pixel (12-bit)
                                                                 │
                                                                 ▼
   sw[11:0] ────────────────────►  pixel_filter  ─► filtered_pixel
                                                                 │
                                                                 ▼
                                                          vga_display
                                                                 │
                                                                 ▼
                                               vga_red/green/blue/hsync/vsync
```

The top module that wires this all together is [ov7670_top.v](src/project_1.srcs/sources_1/new/ov7670_top.v).

---

## RTL source files

All synthesizable Verilog lives in [src/project_1.srcs/sources_1/new/](src/project_1.srcs/sources_1/new/):

| File | Module(s) | Role |
|---|---|---|
| [ov7670_top.v](src/project_1.srcs/sources_1/new/ov7670_top.v) | `ov7670_top` | Top level. Instantiates clock wizard, **`BUFG` on `OV7670_PCLK`** (forces the camera pixel clock onto a dedicated global clock network — without this the source-synchronous capture suffers setup/hold violations and renders as "color snow"), debouncer, SCCB config, capture, frame buffer, pixel filter, VGA controller. |
| [debounce.v](src/project_1.srcs/sources_1/new/debounce.v) | `debounce` | 24-bit counter debouncer on `clk50` (~0.33 s stable window). Used to gate SCCB re-config on the user button. |
| [sccb_sender.v](src/project_1.srcs/sources_1/new/sccb_sender.v) | `I2C_Controller`, `I2C_OV7670_RGB565_Config` | Bit-level I²C/SCCB FSM (read + write) and the 16-bit register LUT (≈194 entries) that puts the OV7670 into RGB565 320×240 mode. The first write is `COM7 = 0x80` (soft reset); subsequent writes program AWB / gamma / colour matrix on a known-good baseline. `HSTART = 0x17` / `HSTOP = 0x05` slide the camera's active window so its horizontal blanking does not bleed into BRAM column 0. |
| [camera_config.v](src/project_1.srcs/sources_1/new/camera_config.v) | `I2C_AV_Config` | High-level driver that walks the LUT, retries on NACK, raises `Config_Done` when finished. A 40 ms start-up delay holds the SCCB FSM idle until the camera is ready to ACK; without it the first few register writes are silently dropped. |
| [camera_capture.v](src/project_1.srcs/sources_1/new/camera_capture.v) | `ov7670_capture` | Assembles two OV7670 bytes into one RGB565 pixel, truncates to RGB444 (12-bit), and emits a registered `(addr, dout, we)` tuple — addressed via `y*320 + x`, all in the buffered **`pclk`** domain. End-of-line is detected from the **HREF falling edge** (not a 320-pixel count) so the writer cannot drift across rows if the camera's per-line cycle count deviates. `x_pos` clamps at 319 to absorb over-shoots. Optional `HREF_SETTLE` localparam skips the first N PCLK cycles of each line if the sensor has an HREF preamble (default 0). |
| [pixel_filter.v](src/project_1.srcs/sources_1/new/pixel_filter.v) | `pixel_filter` | Pure combinational filter bank: raw / weighted grayscale / R-G-B isolate / invert / threshold-binarize. Selected by the user switches (see below). |
| [vga_display.v](src/project_1.srcs/sources_1/new/vga_display.v) | `vga_display` | 640×480 @ 60 Hz timing. Pixel-doubles the 320×240 frame buffer horizontally and vertically; emits address one cycle before reading BRAM and pipelines sync/visible flags accordingly. |

Simulation-only HDL stubs (kept in the Vivado project, not used by cocotb): [tb_i2c_controller.v](src/project_1.srcs/sim_1/new/tb_i2c_controller.v), [tb_pixel_filter.v](src/project_1.srcs/sim_1/new/tb_pixel_filter.v).

Pin constraints: [constrain_1.xdc](src/project_1.srcs/constrs_1/new/constrain_1.xdc) (Basys 3 — VGA on the on-board DAC, OV7670 on Pmod JB, button `btn`, switches `sw[11:0]`, status LEDs).

---

## Vivado IP cores

Generated cores under [src/project_1.gen/sources_1/ip/](src/project_1.gen/sources_1/ip/):

| IP | Purpose |
|---|---|
| `clk_wiz_0` | MMCM. `clk100` → `clk50`, `clk25`, `clk24` (+ two reserved outputs `clk_dbg`, `clk_extra`). |
| `blk_mem_gen_0` | Dual-port BRAM frame buffer. Port A: camera writes on `OV7670_PCLK`. Port B: VGA reads on `clk25`. 12-bit data, 17-bit address (320×240 = 76 800 words). |
| `ila`, `ila_1`, `ila_1_1` | Integrated Logic Analyzers. Debug cores — present in the project but not instantiated in `ov7670_top`. |

---

## User controls

Encoded in [pixel_filter.v](src/project_1.srcs/sources_1/new/pixel_filter.v) and the top-level wiring:

| Switch field | Function |
|---|---|
| `sw[1:0]` | Main mode: `00` raw, `01` grayscale (`Y ≈ 0.30 R + 0.60 G + 0.10 B`, implemented as `(3·R + 6·G + B) >> 4`), `10` single-channel isolation, `11` effects |
| `sw[3:2]` | Sub-mode (when main is `10` or `11`): `00`=R / invert, `01`=G / threshold, `10`=B / —, `11`=passthrough |
| `sw[7:4]` | Threshold value used in binary mode (luma > threshold → white, else black) |
| `btn` | After debounce, resets the SCCB driver so the camera reloads its register LUT |
| `LED[0]` | Lit when `Config_Done` is asserted (SCCB programming finished) |

---

## Clocking summary

| Clock | Source | Used by |
|---|---|---|
| `clk100` | Board crystal (pin W5) | `clk_wiz_0` input |
| `clk50` | MMCM `clk_out1` | `debounce` |
| `clk25` | MMCM `clk_out2` | `vga_display` pixel clock, `I2C_AV_Config` SCCB master clock, BRAM read port |
| `clk24` | MMCM `clk_out4` | Driven out as `OV7670_XCLK` |
| `pclk` | `BUFG(OV7670_PCLK)` | `ov7670_capture`, BRAM write port. The raw camera PCLK enters on a non-CCIO pin, so `CLOCK_DEDICATED_ROUTE FALSE` is set in XDC on the IBUF→BUFG net and `BUFG` is instantiated explicitly in [ov7670_top.v](src/project_1.srcs/sources_1/new/ov7670_top.v) to put the capture clock on a global clock network. |

---

## Simulation (cocotb + Icarus Verilog)

The Python testbenches live in [testbench/](testbench/). Each one is self-contained — it points `cocotb_tools.runner` at the relevant Verilog source and runs its own tests.

Currently on disk:

| Testbench | DUT (`hdl_toplevel`) | Covers |
|---|---|---|
| [debounce_tb.py](testbench/debounce_tb.py) | `debounce` | Short-glitch rejection |
| [camera_capture_tb.py](testbench/camera_capture_tb.py) | `ov7670_capture` | vsync resets x/y/we, single RGB565 → RGB444 pixel, x increments, `addr = y·320 + x` |
| [sccb_sender_tb.py](testbench/sccb_sender_tb.py) | `I2C_Controller` | Full 3-byte I²C write with ACK, reset mid-transaction |
| [pixel_filter_tb.py](testbench/pixel_filter_tb.py) | `pixel_filter` | Passthrough, weighted grayscale, R/G/B isolate, invert, threshold binarize |
| [example.py](testbench/example.py) | — | Cocotb hello-world / template |

Run instructions and ready-to-paste PowerShell commands are in [testbench/HOW_TO_TB.md](testbench/HOW_TO_TB.md). Waveforms land in `testbench/sim_build/<top>.fst` (open with GTKWave).

> Note: `HOW_TO_TB.md` also lists `con3x3_tb`, `classifier_tb`, and `downscale_32x32_tb`. Those modules are referenced in commit history (`6826cb4`) but are **not currently present** in this checkout — the doc is ahead of the working tree.

---

## Repository layout

```
HW_project/
├── README.md                     <- you are here
├── src/                          <- Vivado project root
│   ├── project_1.xpr             <- open this in Vivado
│   ├── project_1.srcs/
│   │   ├── sources_1/new/        <- synthesizable RTL (see table above)
│   │   ├── sim_1/new/            <- Vivado-side testbenches (not used by cocotb)
│   │   └── constrs_1/new/        <- constrain_1.xdc (Basys 3 pinout)
│   ├── project_1.gen/sources_1/ip/  <- generated IP (clk_wiz, BRAM, ILAs)
│   ├── project_1.runs/           <- synth_1 / impl_1 output (bitstream lives here)
│   ├── project_1.cache/, .hw/, .ip_user_files/, .sim/   <- Vivado housekeeping
│   └── vivado*.{jou,log}         <- tool logs
└── testbench/                    <- cocotb Python testbenches
    ├── HOW_TO_TB.md              <- how to run sims
    ├── *_tb.py                   <- one file per DUT
    └── sim_build/                <- generated wavedumps + results.xml
```

---

## Build & program

1. Open [src/project_1.xpr](src/project_1.xpr) in Vivado.
2. Run synthesis → implementation → generate bitstream. Output: `src/project_1.runs/impl_1/ov7670_top.bit`.
3. Connect the OV7670 to Pmod **JB** with the pinout in [constrain_1.xdc](src/project_1.srcs/constrs_1/new/constrain_1.xdc), connect VGA, program the board.
4. `LED[0]` should light a fraction of a second after power-on (SCCB config done); the monitor should show the live, optionally-filtered camera feed. Press `btn` (after the debounce window) to re-send the camera register LUT.
