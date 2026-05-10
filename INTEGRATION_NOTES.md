# Integration Notes — VGA Pipeline

This branch wires up the four Phase 1 modules (`vga_sync`, `frame_capture`,
`frame_buffer`, `filters`) into a single video pipeline and adds the
constraints/testbench needed to flash and demo the full design.

## What's added

### `ov7670_uart_test.srcs/sources_1/new/top.v` (rewritten)
- Shares the existing 25 MHz `clk_div` output between `cam_xclk` and the VGA
  pixel clock — no second clock divider needed.
- Wires `frame_capture` → `frame_buffer` port A (100 MHz writes).
- Wires `vga_sync` + inline pixel scaler → `frame_buffer` port B
  (25 MHz reads).
- Pixel scaler: `addr_b = (pixel_y>>1) * 320 + (pixel_x>>1)`, implemented as
  `(y<<8) + (y<<6) + x`. Gated by `video_active` so blanking-region addresses
  can never index past 76 799.
- `video_active_d` registers the visible-region gate by one pixel clock to
  align with the BRAM's 1-cycle read latency. (Side effect: a 1-pixel
  horizontal shift, invisible on screen.)
- `filters` sits between `dout_b` and the VGA RGB output, driven by `sw[4:0]`.
- UART single-pixel sanity path is preserved (`pixel_capture` + `uart_print`).
- LEDs slimmed to: config_done sticky, frame_done heartbeat, vsync/href/pclk
  sticky-seen, plus a mirror of `sw[4:0]`.

### `ov7670_uart_test.srcs/constrs_1/new/constraints.xdc` (extended)
Added pin assignments for:
- `sw[4:0]` → V17, V16, W16, W17, W15 (filter mode + channel mask)
- VGA RGB444 → R: G19/H19/J19/N19, G: J17/H17/G17/D17, B: N18/L18/K18/J18
- `vga_hs` → P19, `vga_vs` → R19

These are pulled from the Basys 3 master XDC and replace the speculative
VGA_B values that `plan.md` flagged as "not sure".

### `ov7670_uart_test.srcs/sim_1/new/tb_filters.v` (new)
Self-checking testbench covering all four filter modes:
- Mode 00 raw passthrough
- Mode 01 grayscale (verifies `R>>2 + G>>1 + B>>2` math)
- Mode 10 bitwise inversion
- Mode 11 channel isolation (every R/G/B mask combination)

Closes the only remaining Phase 1 testbench gap.

## Switch map (final)

| Switches  | Meaning                                              |
|-----------|------------------------------------------------------|
| SW[1:0]   | Filter mode: `00` raw, `01` gray, `10` invert, `11` isolate |
| SW[2]     | In isolate mode: pass red                            |
| SW[3]     | In isolate mode: pass green                          |
| SW[4]     | In isolate mode: pass blue                           |

## LED map (final)

| LED       | Meaning                                     |
|-----------|---------------------------------------------|
| LED[15]   | `config_done` sticky (solid after SCCB init)|
| LED[14]   | `frame_done` heartbeat (~30 Hz blink)       |
| LED[13]   | VSYNC ever seen high                        |
| LED[12]   | HREF ever seen high                         |
| LED[11]   | PCLK ever toggled                           |
| LED[10:5] | unused (0)                                  |
| LED[4:0]  | mirror of `sw[4:0]`                         |

## Block diagram (data path)

```
                       100 MHz                         25 MHz
                          │                               │
   OV7670 ── frame_capture │──┐                            │
                            │  ▼                            │
                            │  frame_buffer (BRAM 320x240x12)
                            │                              ▲
                            │                              │
                            │   pixel_scaler ── vga_sync ──┘
                            │        │
                            │        ▼
                            │     filters ── vga_r/g/b + hs/vs
                            ▼
                       UART debug
```

## What still needs to be done (before / during VGA test)

1. **Open Vivado, run synth → impl → bitstream.** Expect a few warnings:
   - `CLOCK_DEDICATED_ROUTE` on the 25 MHz divider output — Vivado will
     auto-insert a BUFG. Safe to ignore.
   - `tb_top.v` references the old port list (no `sw` / no VGA outputs).
     Verilog tolerates missing port connections so it still elaborates, but
     don't make it the active sim set — use the per-module testbenches.
2. **Flash and probe LEDs first** — confirm LED[15] solid, LED[14] blinking,
   LED[13:11] all high. If any are dark, the camera ribbon is the problem,
   not the VGA pipeline.
3. **Plug in VGA + monitor.** Expected output: live 320x240 camera feed
   pixel-doubled to 640x480, centered (other 0 pixels are black via the
   `video_active_d` gate).
4. **Sweep SW[1:0]** to verify each filter mode. In isolate mode, toggle
   SW[4:2] to see individual channels.
5. **Verify VGA pin assignments** against the Basys 3 master XDC if anything
   looks wrong on the monitor — the values here are the standard ones, but
   double-check before blaming the design.
6. **Stretch / polish:**
   - Double-check `frame_capture` byte ordering against actual OV7670 output
     using the existing UART debug path — if colors look swapped, the byte
     pair convention in `frame_capture.v` lines 121-128 is the place to flip.
   - Update `plan.md` grading checklist with what passed.
   - Write the final report + block diagram for demo.

## How to test on this branch

```bash
git fetch origin
git checkout integration-vga
# open ov7670_uart_test.xpr in Vivado, run synthesis + implementation
# generate bitstream, flash to Basys 3
```

Sim sanity (any of these work without VGA hardware):
- Set active sim to `tb_filters` — verifies filter math.
- Set active sim to `tb_frame_capture` — verifies RGB565→RGB444 + addr reset.
- Set active sim to `tb_frame_buffer` — verifies dual-port read/write.
- Set active sim to `tb_vga_sync` — verifies VGA timing.
