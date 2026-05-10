# Final Project Plan: Real-Time Video Capture and Processing System

## Current State

We already have a working OV7670 UART test project:
- `camera_config.v` — SCCB init, configures QVGA 320x240 RGB565
- `sccb_master.v` — I2C-like bus driver
- `pixel_capture.v` — captures single center pixel per frame
- `uart_tx.v` / `uart_print.v` — sends pixel hex over UART
- `clk_div.v` — 100MHz -> 25MHz XCLK
- `top.v` — integrates everything with LED debug
- `constraints.xdc` — pin assignments for Basys 3
- Bitstream already built and ready to flash

## Target Architecture

```
100MHz ──┬──> clk_div ──────────> 25MHz XCLK ──> OV7670
         │
         ├──> camera_config ──> sccb_master ──> SCL/SDA ──> OV7670
         │
         ├──> frame_capture <── PCLK, VSYNC, HREF, DATA[7:0]
         │         │
         │         ▼ (write port)
         ├──> frame_buffer (dual-port BRAM, 320x240x12-bit)
         │         │
         │         ▼ (read port)
         ├──> filter ──> pixel_out[11:0]   (SW[1:0] selects filter)
         │         │
         │         ▼
         ├──> vga_sync ──> HSYNC, VSYNC, RGB[11:0] ──> VGA connector
         │
         └──> uart_tx/print (keep for debug)
```

## Memory Budget

- Basys 3 BRAM: 1,800 Kbits (50x 36Kb blocks)
- 320x240 @ 12-bit color = 921,600 bits = 900 Kbits
- Fits within budget (50% utilization)
- 12-bit color: RGB444 (4 bits per channel), downsampled from RGB565

## New Modules to Write

### 1. `vga_sync.v` — VGA Timing Controller
- Generates 640x480 @ 60Hz timing (standard VGA)
- Pixel clock: 25MHz (close enough to 25.175MHz for most monitors)
- Horizontal: 640 visible + 16 front porch + 96 sync + 48 back porch = 800
- Vertical: 480 visible + 10 front porch + 2 sync + 33 back porch = 525
- Outputs: hsync, vsync, pixel_x[9:0], pixel_y[9:0], video_active
- Testbench: verify timing in simulation (no hardware needed)

### 2. `frame_capture.v` — Full Frame Capture
- Replace single-pixel `pixel_capture.v` with full-frame writer
- On each PCLK rising edge during HREF, capture byte pairs (RGB565)
- Convert RGB565 → RGB444 (drop LSBs): R[4:1], G[5:2], B[4:1]
- Write 12-bit pixel to BRAM at sequential address
- Reset address on VSYNC
- Address range: 0 to 76,799 (320 x 240)

### 3. `frame_buffer.v` — Dual-Port BRAM
- Port A: write port (from frame_capture, clocked by system clock)
- Port B: read port (from VGA controller, clocked by system clock)
- 320x240 = 76,800 entries x 12 bits
- Use Vivado block RAM inference or explicit BRAM instantiation
- Handle read-during-write: read-first or no-change mode

### 4. `filter.v` — Image Processing Filters
- Input: 12-bit RGB444 pixel
- Output: 12-bit filtered pixel
- SW[1:0] selects mode:
  - `00` = raw (passthrough)
  - `01` = grayscale (weighted sum using shifts: ~0.25R + 0.5G + 0.25B)
  - `10` = color inversion (~pixel)
  - `11` = color channel isolation (red only, or configurable via SW[3:2])
- Pure combinational logic, no state needed

### 5. `pixel_scaler.v` — 2x Pixel Doubling (or inline in VGA read logic)
- VGA outputs 640x480 but frame buffer is 320x240
- Horizontal: hold each pixel for 2 pixel clocks → pixel_x[9:1] = buffer column
- Vertical: read same row for 2 consecutive lines → pixel_y[9:1] = buffer row
- BRAM read address = pixel_y[9:1] * 320 + pixel_x[9:1]

### 6. Updated `top.v`
- Instantiate all new modules
- Keep UART debug path for sanity checking
- Route SW[1:0] to filter select
- Add VGA output pins (hsync, vsync, vga_r[3:0], vga_g[3:0], vga_b[3:0])
- Update constraints.xdc with VGA pin assignments

## Phase 1: Parallel Development (4 people)

| Person | Module              | Description                                      | Dependencies     |
|--------|---------------------|--------------------------------------------------|------------------|
| 1      | `vga_sync.v`        | VGA timing controller + testbench                | None             |
| 2      | `frame_capture.v`   | Full 320x240 frame capture, writes to BRAM       | None             |
| 3      | `frame_buffer.v`    | Dual-port BRAM wrapper                           | None             |
| 4      | `filter.v`          | 3 image filters + SW mux                         | None             |

All 4 modules can be developed and simulated independently.

## Phase 2: Integration

- Person 1+3: Connect VGA read path → frame_buffer read port → pixel_scaler → VGA output
- Person 2+3: Connect frame_capture write path → frame_buffer write port
- Person 4: Wire filter between frame_buffer read output and VGA RGB output
- Everyone: Write updated `top.v` and `constraints.xdc`
- Flash and test with VGA cable + monitor

## Phase 3: Testing & Polish

- Write testbenches for each module (required for grading — 5 points)
- Verify filter toggling works on switches
- Prepare system block diagram for demo
- Write final report

## Testing Strategy (Before VGA Cable Arrives)

1. **Simulation:** All modules can be fully simulated in Vivado
   - VGA timing: verify HSYNC/VSYNC pulse widths and periods
   - Frame capture: inject fake camera signals, verify BRAM writes
   - Frame buffer: verify read/write at correct addresses
   - Filters: verify pixel transformations
2. **UART sanity check:** Dump a row of pixels via UART to verify frame capture correctness
3. **LED debug:** Use LEDs to show state machine states, frame count, etc.
4. **Hardware test:** Once VGA cable is available, plug in and verify display

## VGA Pin Assignments (Basys 3)

```
VGA_R[3:0] → G1, G6, J2, J3     (active pins, active low accent)
VGA_G[3:0] → J4, H4, K1, K2
VGA_B[3:0] → E7, F5, G4, H3     (check Basys 3 schematic)  (not sure)
VGA_HS     → P19
VGA_VS     → R19
```
Note: Verify these against the Basys 3 schematic/master XDC before use.

## Clock Domains

| Clock        | Frequency | Source           | Used By                          |
|--------------|-----------|------------------|----------------------------------|
| clk (sys)    | 100 MHz   | Basys 3 crystal  | SCCB, UART, control logic        |
| cam_xclk     | 25 MHz    | clk_div (÷4)     | OV7670 master clock              |
| cam_pclk     | ~25 MHz   | OV7670 output    | Pixel data sampling              |
| vga_pclk     | 25 MHz    | clk_div or same  | VGA pixel output                 |

- cam_pclk is an external clock — all camera signals must be synchronized into sys clk domain (already done in current design with 3-stage shift registers)
- VGA pixel clock can reuse the same 25MHz from clk_div

## Grading Checklist

- [x] Phase 1 submission: group formed, 3 filters chosen (5 pts)
- [ ] Testbenches for VGA sync, SCCB, memory, filters (5 pts)
- [ ] Camera configured, video captured and displayed at 320x240 (10 pts)
- [ ] 3 filters implemented and togglable (10 pts)
- [ ] Block diagram, demo, Q&A (5 pts)
- [ ] Clean code + report (5 pts)
- [ ] AI usage disclosure (pass/fail)

## Stretch Goals (Extra Credit, +5 pts max)

- Full 640x480 resolution (requires creative memory management — line buffer approach)
- Ping pong game overlay using camera input for paddle control
- Bilinear upscaling to 1280x960
- Simple NN for detection (e.g., FINN framework)

## Deliverables

1. Source code: all `.v` files, well-commented
2. Constraints: updated `.xdc` with VGA pins
3. Testbenches: one per major module
4. Block diagram: system-level data path + clock domains
5. Final report: architecture, state machines, challenges
6. AI usage declaration
