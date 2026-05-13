# Display Problems — Status

Original symptoms on the live VGA output:

1. **Image clarity** — noisy / "snow" / wrong colors, especially in raw and channel modes. Grayscale looked much cleaner (averaging hid per-bit noise).
2. **Left-edge band** — a vertical strip on the left rendered as a wrong/uniform color, independent of filter mode.

After the fixes below, both original symptoms are resolved. One residual artifact remains, described at the bottom.

---

## Issue 1 — Image clarity (noise / color "snow")  ✅ resolved

Grayscale was dramatically cleaner than raw RGB because grayscale collapses the three channels into one (`Y ≈ 3R + 6G + B`), which averages out per-bit noise — strong evidence the noise was **per-bit / pre-averaging**, upstream of the filter.

### a. PCLK on a non-clock-capable pin  ✅ fixed

[constrain_1.xdc:109](src/project_1.srcs/constrs_1/new/constrain_1.xdc#L109) sets `CLOCK_DEDICATED_ROUTE FALSE` on `OV7670_PCLK_IBUF` because PCLK enters on a non-CCIO pin. Originally that meant the capture clock was routed through fabric — long skew, setup/hold violations on `D[7:0]`, "color snow."

**Fix applied:** explicit `BUFG` instantiation in [ov7670_top.v:88-91](src/project_1.srcs/sources_1/new/ov7670_top.v#L88-L91) forces the buffered `pclk` onto a global clock network. The XDC constraint stays in place to keep Vivado from erroring on the IBUF→BUFG path from a non-CCIO source.

### b. No OV7670 soft-reset before the register write burst  ✅ fixed

The LUT used to start with `COM7 = 0x14` (RGB565 + QVGA) without first soft-resetting the camera, so AWB / gamma writes landed on top of undefined power-on state.

**Fix applied:** new `SOFT_RESET` LUT slot ([sccb_sender.v:283-301](src/project_1.srcs/sources_1/new/sccb_sender.v#L283-L301)) writes `0x12 = 0x80` as the very first SCCB transaction, before the rest of the configuration LUT. The remaining ~165 register writes at 10 kHz SCCB take many milliseconds, which comfortably satisfies the datasheet's ≥1 ms post-reset wait — no explicit delay loop needed.

### c. No start-up delay before SCCB  ✅ fixed

[camera_config.v](src/project_1.srcs/sources_1/new/camera_config.v) used to have the `start_delay` counter commented out, so SCCB writes started before the OV7670 was ready to ACK.

**Fix applied:** counter re-enabled at [camera_config.v:75-88](src/project_1.srcs/sources_1/new/camera_config.v#L75-L88) (1 M cycles ≈ 40 ms at 25 MHz), and the FSM is gated on `start_done` at [camera_config.v:99](src/project_1.srcs/sources_1/new/camera_config.v#L99).

### d. AWB / saturation / gamma values in the LUT  ⚠ not audited

Not investigated. With ~165 LUT entries it is still possible a magic number is wrong. If colors look off after all other fixes, diff against a known-good OV7670 RGB565 register set (Adafruit / SparkFun publish them).

### e. Pipeline race in `camera_capture`  ✅ fixed

Originally `we`, `addr`, and `dout` were all driven combinationally from registers that updated on the same `pclk` edge as the BRAM write — so the address presented to the BRAM advanced one position ahead of the data (pixel `N` landed at addr `N+1`, and addr 0 was never written).

**Fix applied:** added an output pipeline stage at [camera_capture.v:111-138](src/project_1.srcs/sources_1/new/camera_capture.v#L111-L138). `addr_q`, `dout_q`, and `we_q` are all registered together one cycle later, so the BRAM samples a consistent `(addr, data, we)` tuple aligned to the same pixel.

---

## Issue 2 — Left-edge band  ✅ resolved

Independent of filter mode, so not in the filter. Solid "different content" (not black), so not VGA sync timing. The band was in **framebuffer addressing**.

### a. HSTART / HSTOP windowing mistuned  ✅ fixed

Original values had the camera's active window starting in its horizontal blanking, so the first ~16 captured pixels per row were low-saturation border values that landed in BRAM columns 0..N.

**Fix applied:** slid the window in [sccb_sender.v:309-310](src/project_1.srcs/sources_1/new/sccb_sender.v#L309-L310). `HSTART` bumped `0x13 → 0x17` and `HSTOP` bumped `0x01 → 0x05`. Both endpoints moved by the same +4 register units, so the active window stays 640 sensor pixels wide (= 320 QVGA captured) but starts 32 sensor pixels later in the line cycle — past the blanking.

> **Why both?** Bumping only `HSTART` slides the *start* of the window but shrinks its width, leaving the right edge of BRAM unwritten instead of the left. Bumping both by the same delta is a translation, not a width change.

### b. HREF asserts before pixel data is valid  ✅ addressed, gate currently disabled

Some OV7670 batches assert HREF a few PCLK cycles before `D[7:0]` is valid. To handle that we added an `HREF_SETTLE` localparam in [camera_capture.v:43](src/project_1.srcs/sources_1/new/camera_capture.v#L43) that skips the first N PCLK cycles of every line.

After the HSTART tuning in 2-a, HREF rises exactly on the first valid byte for this particular sensor, so `HREF_SETTLE` is set to `3'd0` (gate disabled). Every skipped cycle is a pixel dropped from the start of each row, which would leave the same number of unwritten columns on the right — so the gate is only useful if the sensor really does have a preamble. Bump in **even** increments (to preserve byte_phase alignment) if your specific batch needs it.

### c. BRAM column 0 stays at init value  ✅ fixed by 1-e

The pipeline race in 1-e was what kept address 0 stuck at the BRAM's init value. Fixed by the same registered output stage.

### d. Address calculation mismatch  ✅ effectively fixed

Writer (`y_pos * 320 + x_pos` in [camera_capture.v:135](src/project_1.srcs/sources_1/new/camera_capture.v#L135)) and reader (`src_y * 320 + src_x` in [vga_display.v:86](src/project_1.srcs/sources_1/new/vga_display.v#L86)) use the same formula. The writer's `(y_pos, x_pos)` state is now driven from HREF transitions (next section) rather than a 320-pixel count, so the writer cannot drift relative to the reader's expectation.

---

## Issue 3 — Diagonal shear (introduced and then fixed during this debug pass)

While iterating on the `HREF_SETTLE` gate the image came back as a steeply sheared diagonal — each row offset right of the previous by ~2 pixels.

**Cause:** with `HREF_SETTLE = 4` the capture dropped ~2 pixels per HREF window, so `x_pos` only reached 317 each row instead of 319. The original line-end logic was `if (x_pos == 319) ... y_pos <= y_pos + 1`, so `y_pos` never advanced — the next HREF window kept writing into the *same* row starting at `x = 318`, wrapped mid-row, and bled into row 1, row 2 …. The 2-pixel-per-row error integrated over 240 rows into a full-screen diagonal.

**Fix applied:** in [camera_capture.v:108-128](src/project_1.srcs/sources_1/new/camera_capture.v#L108-L128) the row counter is now driven from the **HREF falling edge** — `x_pos` resets to 0 and `y_pos` increments on every HREF fall regardless of pixel count. Pixel-count clamp at 319 prevents overshoot if the camera ever sends >320 pixels per HREF. Robust to any per-line length mismatch.

---

## Remaining artifact — thin green line on the right edge

After all the above, the live picture is clean except for a **1–2 column-wide green stripe at the right edge** of every row.

Most likely cause: the camera's `HREF` falls one to two PCLK cycles *after* it stops driving fresh pixel data on `D[7:0]` (a trailing pad pattern that the OV7670 emits during the HREF→0 transition). Those last 1–2 bytes still get assembled and written, with an alignment that lands greenish in RGB565 → RGB444. The bytes are real BRAM writes, not stale data — they reach `x_pos = 318` or `319` before HREF falls, so they aren't unwritten pixels.

### Things to try (cheap first)

1. **Lower `HSTOP` by 1 unit** ([sccb_sender.v:310](src/project_1.srcs/sources_1/new/sccb_sender.v#L310), `16'h1805` → `16'h1804`). That asks the camera to end its active window one register-unit (= 8 sensor pixels = 4 captured pixels = 8 VGA pixels with our doubling) sooner. Lose 4 captured pixels of real image on the right, but the trailing junk goes away.
2. **Gate the writer at `x_pos >= 318`** — suppress `we_q` for the last column or two so the trailing bytes can't be written. Cleaner than tuning the camera, but bakes a one-off mask into the writer.
3. **Probe with the ILA** — capture `pclk`, `href`, `D[7:0]` at the HREF-fall boundary and look at what the camera actually puts on the bus in the last 2-4 cycles. That tells you whether the junk is sensor padding (fix in HSTOP) or our byte_phase getting out of sync at end of line (fix in writer).

---

## Summary of code changes applied

| Issue | File | Change |
|---|---|---|
| 1-a (PCLK fabric routing) | [ov7670_top.v:76-91](src/project_1.srcs/sources_1/new/ov7670_top.v#L76-L91) | Added explicit `BUFG` on `OV7670_PCLK`; routed buffered `pclk` to capture + BRAM. |
| 1-b (no soft reset) | [sccb_sender.v:284, :290-300](src/project_1.srcs/sources_1/new/sccb_sender.v#L284) | Added `SOFT_RESET` parameter and LUT entry `0x12=0x80`; shifted `SET_OV7670` base to 3. |
| 1-b (LUT size) | [camera_config.v:20](src/project_1.srcs/sources_1/new/camera_config.v#L20) | `LUT_SIZE` 193 → 194. |
| 1-c (no SCCB start delay) | [camera_config.v:75-88, :99](src/project_1.srcs/sources_1/new/camera_config.v#L75-L88) | Re-enabled `start_delay` (40 ms); gated FSM on `start_done`. |
| 1-e (writer pipeline race) | [camera_capture.v:111-138](src/project_1.srcs/sources_1/new/camera_capture.v#L111-L138) | Registered `addr_q` / `dout_q` / `we_q` so BRAM sees a consistent tuple. |
| 2-a (HSTART/HSTOP) | [sccb_sender.v:309-310](src/project_1.srcs/sources_1/new/sccb_sender.v#L309-L310) | `HSTART` `0x13 → 0x17`, `HSTOP` `0x01 → 0x05` (window slide, same width). |
| 2-b (HREF preamble gate) | [camera_capture.v:31-43, :70](src/project_1.srcs/sources_1/new/camera_capture.v#L31-L43) | Added `HREF_SETTLE` localparam + counter; currently `3'd0`. |
| 3 (line termination) | [camera_capture.v:108-128](src/project_1.srcs/sources_1/new/camera_capture.v#L108-L128) | Switched to HREF-fall end-of-line; `x_pos` clamps at 319. |
